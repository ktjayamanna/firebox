import boto3
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, validator
from typing import List, Optional, Dict, Any
import uuid
from datetime import datetime
import os
import logging
import json

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/tmp/files_service.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

from models import FilesMetaData, Chunks, Folders, create_tables
from s3_utils import generate_presigned_urls, complete_multipart_upload, abort_multipart_upload
import config

logger.info("Files Service starting up")

logger.info("Creating DynamoDB tables if they don't exist")
create_tables()

app = FastAPI(
    title="Files Service API",
    description="API for handling file metadata and multipart uploads",
    version="0.1.0"
)

# Pydantic models for request/response
class FileMetaRequest(BaseModel):
    file_name: str
    file_path: str
    file_type: str
    folder_id: str
    chunk_count: int
    file_hash: Optional[str] = None

class PresignedUrlResponse(BaseModel):
    chunk_id: str
    presigned_url: str
    part_number: Optional[int] = None
    upload_id: Optional[str] = None

class FileMetaResponse(BaseModel):
    file_id: str
    presigned_urls: List[PresignedUrlResponse]

class ChunkETagInfo(BaseModel):
    chunk_id: str
    part_number: int
    etag: str
    fingerprint: str  # Make fingerprint required

class ChunkConfirmRequest(BaseModel):
    file_id: str
    chunk_ids: List[str]
    chunk_etags: Optional[List[Dict[str, Any]]] = None
    
    @validator('chunk_etags')
    def validate_chunk_etags(cls, v):
        if v is not None:
            for i, chunk_info in enumerate(v):
                # Check if chunk_id is present
                if 'chunk_id' not in chunk_info:
                    raise ValueError(f"chunk_etags[{i}] missing required field 'chunk_id'")
                
                # Check if etag is present
                if 'etag' not in chunk_info:
                    raise ValueError(f"chunk_etags[{i}] missing required field 'etag'")
                
                # Check if fingerprint is present
                if 'fingerprint' not in chunk_info:
                    raise ValueError(f"chunk_etags[{i}] missing required field 'fingerprint'")
                elif not chunk_info['fingerprint']:
                    raise ValueError(f"chunk_etags[{i}] has empty fingerprint")
        return v

class ChunkConfirmResponse(BaseModel):
    file_id: str
    confirmed_chunks: int
    success: bool

@app.get("/health")
def health_check():
    """Health check endpoint"""
    return {"status": "healthy"}

@app.post("/files", response_model=FileMetaResponse)
async def create_file(file_meta: FileMetaRequest):
    """
    Receive file metadata and generate presigned URLs for multipart upload
    """
    # Generate a unique file ID
    file_id = str(uuid.uuid4())

    # Create file metadata in DynamoDB
    try:
        file_metadata = FilesMetaData(
            file_id=file_id,
            file_type=file_meta.file_type,
            file_path=file_meta.file_path,
            file_name=file_meta.file_name,
            folder_id=file_meta.folder_id,
            file_hash=file_meta.file_hash
        )
        file_metadata.save()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to create file metadata: {str(e)}")

    # Generate presigned URLs for multipart upload
    try:
        presigned_urls_data = generate_presigned_urls(file_id, file_meta.chunk_count)

        # Get the upload ID from the first presigned URL (all have the same upload ID)
        upload_id = presigned_urls_data[0]['upload_id'] if presigned_urls_data else None

        # Store the upload ID in the file metadata
        file_metadata.upload_id = upload_id
        file_metadata.save()
    except Exception as e:
        # Clean up file metadata if presigned URL generation fails
        try:
            file_metadata.delete()
        except:
            pass
        raise HTTPException(status_code=500, detail=f"Failed to generate presigned URLs: {str(e)}")

    # Create chunk entries in DynamoDB with null last_synced
    try:
        for i, url_data in enumerate(presigned_urls_data):
            chunk_id = url_data['chunk_id']
            part_number = url_data['part_number']

            chunk = Chunks(
                chunk_id=chunk_id,
                file_id=file_id,
                part_number=part_number,
                created_at=datetime.utcnow(),
                last_synced=None,
                etag=None,
                fingerprint=""  # Will be updated when chunk is uploaded
            )
            chunk.save()
    except Exception as e:
        # Clean up file metadata and abort multipart upload if chunk creation fails
        try:
            file_metadata.delete()
            if upload_id:
                abort_multipart_upload(file_id, upload_id)
        except:
            pass
        raise HTTPException(status_code=500, detail=f"Failed to create chunk entries: {str(e)}")

    # Format the response to match the expected client format
    # Only include chunk_id and presigned_url in the response to maintain client compatibility
    formatted_presigned_urls = [
        {"chunk_id": url_data["chunk_id"], "presigned_url": url_data["presigned_url"]}
        for url_data in presigned_urls_data
    ]

    return {
        "file_id": file_id,
        "presigned_urls": formatted_presigned_urls
    }

@app.post("/files/confirm", response_model=ChunkConfirmResponse)
async def confirm_chunks(confirm_request: ChunkConfirmRequest):
    """
    Confirm successful multipart upload and update chunk status
    """
    file_id = confirm_request.file_id
    chunk_ids = confirm_request.chunk_ids

    # Print to stdout for immediate visibility in logs
    print(f"Confirming chunks for file {file_id}: {chunk_ids}")
    print(f"Chunk ETags data: {confirm_request.chunk_etags}")

    # Log to logger as well
    logger.info(f"Confirming chunks for file {file_id}: {chunk_ids}")
    logger.info(f"Chunk ETags data: {confirm_request.chunk_etags}")

    # Verify file exists
    try:
        file_metadata = FilesMetaData.get(file_id)
        upload_id = file_metadata.upload_id
        logger.info(f"Found file metadata with upload_id: {upload_id}")

        if not upload_id:
            logger.error(f"No active multipart upload found for file {file_id}")
            raise HTTPException(status_code=400, detail=f"No active multipart upload found for file {file_id}")
    except Exception as e:
        logger.error(f"Error getting file metadata: {str(e)}")
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=404, detail=f"File with ID {file_id} not found")

    # Update chunk status and collect parts for completing multipart upload
    confirmed_count = 0
    parts = []

    try:
        # Get all chunks for this file to collect ETags
        all_chunks = list(Chunks.query(file_id, Chunks.file_id == file_id))
        logger.info(f"Found {len(all_chunks)} chunks for file {file_id}")

        # Check if all chunks are confirmed
        all_confirmed = True

        # Create a mapping of chunk_id to ETag info if provided
        etag_map = {}
        if confirm_request.chunk_etags:
            logger.info(f"Processing {len(confirm_request.chunk_etags)} chunk ETags from request")
            for chunk_info in confirm_request.chunk_etags:
                # Handle both object and dictionary formats
                chunk_id = chunk_info.get('chunk_id') if isinstance(chunk_info, dict) else chunk_info.chunk_id
                part_number = chunk_info.get('part_number') if isinstance(chunk_info, dict) else chunk_info.part_number
                etag = chunk_info.get('etag') if isinstance(chunk_info, dict) else chunk_info.etag
                fingerprint = chunk_info.get('fingerprint', '') if isinstance(chunk_info, dict) else getattr(chunk_info, 'fingerprint', '')

                # Check if fingerprint is missing or empty
                if not fingerprint:
                    error_msg = f"ERROR: Missing required fingerprint for chunk {chunk_id}"
                    print(error_msg)
                    logger.error(error_msg)
                    # You could raise an exception here if fingerprints are absolutely required
                    # raise HTTPException(status_code=400, detail=f"Missing required fingerprint for chunk {chunk_id}")
                    
                    # Or set a placeholder fingerprint for debugging
                    fingerprint = f"MISSING-FINGERPRINT-{chunk_id}"
                    print(f"Using placeholder fingerprint: {fingerprint}")
                    logger.warning(f"Using placeholder fingerprint: {fingerprint}")

                # Log the raw ETag and fingerprint values for debugging
                print(f"Raw ETag from client for chunk {chunk_id}: '{etag}'")
                print(f"Raw fingerprint from client for chunk {chunk_id}: '{fingerprint}'")
                logger.info(f"Raw ETag from client for chunk {chunk_id}: '{etag}'")
                logger.info(f"Raw fingerprint from client for chunk {chunk_id}: '{fingerprint}'")

                etag_map[chunk_id] = {
                    'part_number': part_number,
                    'etag': etag,
                    'fingerprint': fingerprint
                }
                logger.info(f"Added chunk info for {chunk_id}: part_number={part_number}, etag={etag}, fingerprint={fingerprint}")

        # Process chunks from database
        print(f"Processing chunks for file {file_id}")
        logger.info(f"Processing chunks for file {file_id}")

        # Debug dump of etag_map
        import json
        print(f"ETAG_MAP DUMP: {json.dumps(etag_map, indent=2)}")
        logger.info(f"ETAG_MAP DUMP: {json.dumps(etag_map, indent=2)}")
        print(f"CHUNK_IDS WE'RE LOOKING FOR: {chunk_ids}")
        logger.info(f"CHUNK_IDS WE'RE LOOKING FOR: {chunk_ids}")

        # Find all chunks for this file using scan with filter
        try:
            # Use scan with filter to find all chunks for this file
            all_chunks = list(Chunks.scan(Chunks.file_id == file_id))
            print(f"Found {len(all_chunks)} chunks for file {file_id} using scan")
            logger.info(f"Found {len(all_chunks)} chunks for file {file_id} using scan")
            
            # Create a map of chunk_id to chunk object for easier lookup
            chunk_map = {chunk.chunk_id: chunk for chunk in all_chunks}
            
            # Process each chunk from the request
            confirmed_count = 0
            parts = []
            
            for chunk_id in chunk_ids:
                # Check if the chunk exists in our map
                if chunk_id in chunk_map:
                    chunk = chunk_map[chunk_id]
                    print(f"Found chunk {chunk_id} in database")
                    logger.info(f"Found chunk {chunk_id} in database")
                else:
                    print(f"Chunk {chunk_id} not found in database, creating it")
                    logger.info(f"Chunk {chunk_id} not found in database, creating it")
                    
                    # If the chunk doesn't exist, create it
                    if chunk_id in etag_map:
                        chunk_info = etag_map[chunk_id]
                        chunk = Chunks(
                            chunk_id=chunk_id,
                            file_id=file_id,
                            part_number=chunk_info['part_number'],
                            created_at=datetime.utcnow(),
                            fingerprint=chunk_info['fingerprint'],
                            etag=chunk_info['etag']
                        )
                        chunk.save()
                        print(f"Created chunk {chunk_id} in database")
                        logger.info(f"Created chunk {chunk_id} in database")
                    else:
                        print(f"No info available for chunk {chunk_id}, skipping")
                        logger.warning(f"No info available for chunk {chunk_id}, skipping")
                        continue
                
                # Use ETag from client if available
                if chunk_id in etag_map:
                    etag_value = etag_map[chunk_id]['etag']
                    print(f"DEBUG: Raw ETag from client for chunk {chunk_id}: '{etag_value}'")
                    logger.info(f"DEBUG: Raw ETag from client for chunk {chunk_id}: '{etag_value}'")
                    
                    # Check if ETag has quotes
                    has_quotes = etag_value.startswith('"') and etag_value.endswith('"')
                    print(f"DEBUG: ETag has quotes: {has_quotes}")
                    logger.info(f"DEBUG: ETag has quotes: {has_quotes}")
                    
                    print(f"USING CLIENT ETAG for chunk {chunk_id}: '{etag_value}'")
                    logger.info(f"USING CLIENT ETAG for chunk {chunk_id}: '{etag_value}'")

                    # Get fingerprint from etag_map
                    fingerprint_value = etag_map[chunk_id].get('fingerprint', '')
                    print(f"USING FINGERPRINT for chunk {chunk_id}: '{fingerprint_value}'")
                    logger.info(f"USING FINGERPRINT for chunk {chunk_id}: '{fingerprint_value}'")

                    # Update chunk with ETag and fingerprint
                    try:
                        chunk.etag = etag_value
                        chunk.fingerprint = fingerprint_value
                        chunk.last_synced = datetime.utcnow()
                        print(f"ATTEMPTING TO SAVE CHUNK {chunk.chunk_id} with etag={etag_value}, fingerprint={fingerprint_value}")
                        logger.info(f"ATTEMPTING TO SAVE CHUNK {chunk.chunk_id} with etag={etag_value}, fingerprint={fingerprint_value}")
                        
                        # Save with exception details
                        try:
                            chunk.save()
                            print(f"SAVE SUCCESSFUL for chunk {chunk.chunk_id}")
                            logger.info(f"SAVE SUCCESSFUL for chunk {chunk.chunk_id}")
                        except Exception as save_error:
                            print(f"SAVE FAILED for chunk {chunk.chunk_id}: {str(save_error)}")
                            logger.error(f"SAVE FAILED for chunk {chunk.chunk_id}: {str(save_error)}")
                            # Log the full exception traceback
                            import traceback
                            print(f"SAVE ERROR TRACEBACK: {traceback.format_exc()}")
                            logger.error(f"SAVE ERROR TRACEBACK: {traceback.format_exc()}")
                            raise save_error

                        # Add to parts list for completing multipart upload
                        try:
                            # Ensure ETag has quotes for S3/MinIO
                            if not (etag_value.startswith('"') and etag_value.endswith('"')):
                                etag_value = etag_value.strip('"')
                                etag_value = f'"{etag_value}"'
                                print(f"DEBUG: Added quotes to ETag for S3: '{etag_value}'")
                                logger.info(f"DEBUG: Added quotes to ETag for S3: '{etag_value}'")
                            
                            parts.append({
                                'PartNumber': int(chunk.part_number),
                                'ETag': etag_value
                            })
                            print(f"ADDED TO PARTS LIST: PartNumber={chunk.part_number}, ETag={etag_value}")
                            logger.info(f"ADDED TO PARTS LIST: PartNumber={chunk.part_number}, ETag={etag_value}")
                            confirmed_count += 1
                        except Exception as parts_error:
                            print(f"FAILED TO ADD TO PARTS LIST: {str(parts_error)}")
                            logger.error(f"FAILED TO ADD TO PARTS LIST: {str(parts_error)}")
                            raise parts_error
                    except Exception as update_error:
                        print(f"UPDATE FAILED for chunk {chunk.chunk_id}: {str(update_error)}")
                        logger.error(f"UPDATE FAILED for chunk {chunk.chunk_id}: {str(update_error)}")
                        raise update_error
                else:
                    print(f"No ETag info available for chunk {chunk_id}, skipping")
                    logger.warning(f"No ETag info available for chunk {chunk_id}, skipping")
        except Exception as e:
            print(f"Error processing chunks: {str(e)}")
            logger.error(f"Error processing chunks: {str(e)}")
            # Log the full exception traceback
            import traceback
            print(f"PROCESSING ERROR TRACEBACK: {traceback.format_exc()}")
            logger.error(f"PROCESSING ERROR TRACEBACK: {traceback.format_exc()}")

        # Log the final parts list
        print(f"FINAL PARTS LIST: {json.dumps(parts, indent=2)}")
        logger.info(f"FINAL PARTS LIST: {json.dumps(parts, indent=2)}")
        print(f"CONFIRMED COUNT: {confirmed_count} out of {len(chunk_ids)} requested")
        logger.info(f"CONFIRMED COUNT: {confirmed_count} out of {len(chunk_ids)} requested")

        # If we have parts, proceed with completion
        if len(parts) > 0:
            # Sort parts by part number
            parts.sort(key=lambda x: x['PartNumber'])

            print(f"Completing multipart upload for file {file_id} with {len(parts)} parts")
            print(f"Parts: {parts}")
            logger.info(f"Completing multipart upload for file {file_id} with {len(parts)} parts")
            logger.info(f"Parts: {parts}")

            # Complete the multipart upload
            try:
                # Use the s3_utils helper
                response = complete_multipart_upload(file_id, upload_id, parts)
                print(f"Multipart upload response: {response}")
                logger.info(f"Multipart upload response: {response}")

                # Store the ETag of the complete file
                file_metadata.complete_etag = response.get('ETag', '')
                file_metadata.save()

                print(f"Multipart upload completed for file {file_id}")
                logger.info(f"Multipart upload completed for file {file_id}")
            except Exception as complete_error:
                print(f"Error completing multipart upload: {str(complete_error)}")
                logger.error(f"Error completing multipart upload: {str(complete_error)}")
        else:
            print(f"No parts available for file {file_id}, cannot complete multipart upload")
            logger.warning(f"No parts available for file {file_id}, cannot complete multipart upload")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update chunks: {str(e)}")

    return {
        "file_id": file_id,
        "confirmed_chunks": confirmed_count,
        "success": confirmed_count == len(chunk_ids)
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=config.API_HOST,
        port=config.API_PORT,
        reload=True
    )
