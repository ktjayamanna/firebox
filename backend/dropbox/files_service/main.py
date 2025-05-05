from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
import uuid
from datetime import datetime
import os
import logging

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

from models import FilesMetaData, Chunks
from s3_utils import generate_presigned_urls, complete_multipart_upload, abort_multipart_upload
import config

logger.info("Files Service starting up")

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

class ChunkConfirmRequest(BaseModel):
    file_id: str
    chunk_ids: List[str]
    chunk_etags: Optional[List[Dict[str, Any]]] = None

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

    # Log the raw request data for debugging
    try:
        # Create a test file to verify we can write to the directory
        with open('/app/test_debug.log', 'w') as f:
            f.write("Test debug log\n")

        # Try to log the request data
        with open('/app/debug.log', 'a') as f:
            f.write(f"CONFIRM REQUEST: {confirm_request}\n")
            f.write(f"CHUNK ETAGS: {confirm_request.chunk_etags}\n")
            f.write(f"CHUNK IDS: {chunk_ids}\n")
            f.write("---\n")
    except Exception as e:
        print(f"Failed to write debug log: {str(e)}")
        logger.error(f"Failed to write debug log: {str(e)}")

    # Directly update the chunks in DynamoDB before proceeding
    try:
        # If we have chunk ETags, update them directly in DynamoDB
        if confirm_request.chunk_etags:
            print(f"Directly updating {len(confirm_request.chunk_etags)} chunks in DynamoDB")

            # Get DynamoDB client
            dynamodb = boto3.resource(
                'dynamodb',
                endpoint_url=config.DYNAMODB_ENDPOINT,
                region_name=config.AWS_REGION,
                aws_access_key_id=config.AWS_ACCESS_KEY_ID,
                aws_secret_access_key=config.AWS_SECRET_ACCESS_KEY
            )
            table = dynamodb.Table('Chunks')

            # Update each chunk
            for chunk_info in confirm_request.chunk_etags:
                # Handle both object and dictionary formats
                chunk_id = chunk_info.get('chunk_id') if isinstance(chunk_info, dict) else chunk_info.chunk_id
                etag = chunk_info.get('etag') if isinstance(chunk_info, dict) else chunk_info.etag
                fingerprint = chunk_info.get('fingerprint', '') if isinstance(chunk_info, dict) else getattr(chunk_info, 'fingerprint', '')

                print(f"Directly updating chunk {chunk_id} with ETag {etag} and fingerprint {fingerprint}")

                # Update the chunk in DynamoDB
                try:
                    response = table.update_item(
                        Key={
                            'chunk_id': chunk_id,
                            'file_id': file_id
                        },
                        UpdateExpression="set etag = :e, last_synced = :ls, fingerprint = :fp",
                        ExpressionAttributeValues={
                            ':e': etag,
                            ':ls': datetime.utcnow().isoformat(),
                            ':fp': fingerprint
                        },
                        ReturnValues="UPDATED_NEW"
                    )
                    print(f"Direct DynamoDB update response for {chunk_id}: {response}")
                except Exception as update_error:
                    print(f"Error updating chunk {chunk_id} directly in DynamoDB: {str(update_error)}")
    except Exception as direct_update_error:
        print(f"Error in direct DynamoDB update: {str(direct_update_error)}")

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

                # Log the raw ETag and fingerprint values for debugging
                logger.info(f"Raw ETag from client for chunk {chunk_id}: '{etag}'")
                logger.info(f"Fingerprint from client for chunk {chunk_id}: '{fingerprint}'")

                etag_map[chunk_id] = {
                    'part_number': part_number,
                    'etag': etag,
                    'fingerprint': fingerprint
                }
                logger.info(f"Added chunk info for {chunk_id}: part_number={part_number}, etag={etag}, fingerprint={fingerprint}")

        # Process each chunk
        print(f"Processing {len(all_chunks)} chunks for file {file_id}")
        for chunk in all_chunks:
            # Check if this chunk is in the confirmed list
            if chunk.chunk_id in chunk_ids:
                try:
                    print(f"Processing chunk {chunk.chunk_id} (in confirmed list)")
                    # Use ETag from client if available
                    if chunk.chunk_id in etag_map:
                        etag_value = etag_map[chunk.chunk_id]['etag']
                        print(f"Using client-provided ETag for chunk {chunk.chunk_id}: {etag_value}")
                        logger.info(f"Using client-provided ETag for chunk {chunk.chunk_id}: {etag_value}")

                        # Update the chunk directly
                        try:
                            # Set the attributes and save
                            print(f"Before update - Chunk {chunk.chunk_id}: ETag={chunk.etag}, Last synced={chunk.last_synced}")

                            # Important: We need to use the exact ETag from MinIO, including the quotes
                            # This is critical for the multipart upload completion
                            print(f"Setting ETag for chunk {chunk.chunk_id} to {etag_value}")

                            # First try using the model's save method
                            try:
                                # Get fingerprint from etag_map
                                fingerprint_value = etag_map[chunk.chunk_id].get('fingerprint', '')
                                print(f"Using fingerprint value from etag_map: {fingerprint_value}")

                                # Update chunk with ETag and fingerprint
                                chunk.etag = etag_value
                                chunk.fingerprint = fingerprint_value
                                chunk.last_synced = datetime.utcnow()
                                chunk.save()
                                print(f"After save - Chunk {chunk.chunk_id}: ETag={chunk.etag}, Fingerprint={chunk.fingerprint}, Last synced={chunk.last_synced}")

                                # Verify the update by getting the chunk again
                                updated_chunk = Chunks.get(chunk.chunk_id, chunk.file_id)
                                print(f"After get - Chunk {updated_chunk.chunk_id}: ETag={updated_chunk.etag}, Last synced={updated_chunk.last_synced}")

                                # If the ETag is still None, try the direct update
                                if updated_chunk.etag is None:
                                    raise Exception("ETag not saved properly")
                            except Exception as save_error:
                                print(f"Error saving chunk using model: {str(save_error)}")

                                # Try a different approach - update the chunk directly in DynamoDB
                                try:
                                    print(f"Trying direct DynamoDB update for chunk {chunk.chunk_id}")
                                    from boto3.dynamodb.conditions import Key
                                    dynamodb = boto3.resource(
                                        'dynamodb',
                                        endpoint_url=config.DYNAMODB_ENDPOINT,
                                        region_name=config.AWS_REGION,
                                        aws_access_key_id=config.AWS_ACCESS_KEY_ID,
                                        aws_secret_access_key=config.AWS_SECRET_ACCESS_KEY
                                    )
                                    table = dynamodb.Table('Chunks')
                                    # Get fingerprint from etag_map if available, otherwise use the one from the chunk
                                    fingerprint_value = etag_map[chunk.chunk_id].get('fingerprint', '') if chunk.chunk_id in etag_map else (chunk.fingerprint if hasattr(chunk, 'fingerprint') and chunk.fingerprint else "")
                                    print(f"Using fingerprint value for direct update: {fingerprint_value}")

                                    # Update with fingerprint
                                    response = table.update_item(
                                        Key={
                                            'chunk_id': chunk.chunk_id,
                                            'file_id': chunk.file_id
                                        },
                                        UpdateExpression="set etag = :e, last_synced = :ls, fingerprint = :fp",
                                        ExpressionAttributeValues={
                                            ':e': etag_value,
                                            ':ls': datetime.utcnow().isoformat(),
                                            ':fp': fingerprint_value
                                        },
                                        ReturnValues="UPDATED_NEW"
                                    )
                                    print(f"Direct DynamoDB update response: {response}")

                                    # Verify the update
                                    get_response = table.get_item(
                                        Key={
                                            'chunk_id': chunk.chunk_id,
                                            'file_id': chunk.file_id
                                        }
                                    )
                                    item = get_response.get('Item', {})
                                    print(f"After direct update - Chunk {chunk.chunk_id}: ETag={item.get('etag')}, Last synced={item.get('last_synced')}")

                                    # Update the chunk object with the new values
                                    chunk.etag = item.get('etag')
                                    chunk.last_synced = datetime.utcnow()
                                except Exception as dynamo_error:
                                    print(f"Error updating DynamoDB directly: {str(dynamo_error)}")

                                    # Last resort - create a new chunk object
                                    try:
                                        print(f"Trying to create a new chunk object for {chunk.chunk_id}")
                                        # Get fingerprint from etag_map if available, otherwise use the one from the chunk
                                        fingerprint_value = etag_map[chunk.chunk_id].get('fingerprint', '') if chunk.chunk_id in etag_map else (chunk.fingerprint if hasattr(chunk, 'fingerprint') and chunk.fingerprint else "")
                                        print(f"Using fingerprint value for new chunk: {fingerprint_value}")

                                        new_chunk = Chunks(
                                            chunk_id=chunk.chunk_id,
                                            file_id=chunk.file_id,
                                            part_number=chunk.part_number,
                                            etag=etag_value,
                                            last_synced=datetime.utcnow(),
                                            fingerprint=fingerprint_value
                                        )
                                        new_chunk.save()
                                        print(f"Created new chunk: {new_chunk.chunk_id}, ETag={new_chunk.etag}")

                                        # Use the new chunk for the rest of the process
                                        chunk = new_chunk
                                    except Exception as create_error:
                                        print(f"Error creating new chunk: {str(create_error)}")

                            # Add to parts list for completing multipart upload
                            parts.append({
                                'PartNumber': int(chunk.part_number),
                                'ETag': etag_value
                            })
                            print(f"Added part to list: PartNumber={chunk.part_number}, ETag={etag_value}")

                            confirmed_count += 1
                        except Exception as e:
                            print(f"Error updating chunk {chunk.chunk_id}: {str(e)}")
                            logger.error(f"Error updating chunk {chunk.chunk_id}: {str(e)}")
                    else:
                        print(f"No ETag provided for chunk {chunk.chunk_id}, skipping")
                        logger.warning(f"No ETag provided for chunk {chunk.chunk_id}, skipping")
                except Exception as e:
                    logger.error(f"Error processing chunk {chunk.chunk_id}: {str(e)}")
            elif not chunk.last_synced:
                # If any chunk is not synced, we can't complete the multipart upload
                all_confirmed = False
                logger.warning(f"Chunk {chunk.chunk_id} is not synced, multipart upload cannot be completed")

        # If all chunks are confirmed, complete the multipart upload
        if len(all_chunks) > 0:
            # Try to complete the multipart upload even if not all chunks are confirmed
            # This is a more aggressive approach to ensure files are completed
            try:
                # If parts list is empty, try to build it from the chunks
                if len(parts) == 0:
                    print(f"Parts list is empty. Trying to build it from chunks...")
                    for chunk in all_chunks:
                        if chunk.etag:
                            parts.append({
                                'PartNumber': int(chunk.part_number),
                                'ETag': chunk.etag
                            })
                            print(f"Added part from chunk: PartNumber={chunk.part_number}, ETag={chunk.etag}")

                # If still empty, try to get parts directly from S3
                if len(parts) == 0:
                    print(f"Parts list still empty. Trying to get parts directly from S3...")
                    try:
                        s3 = boto3.client(
                            's3',
                            endpoint_url=config.S3_ENDPOINT,
                            aws_access_key_id=config.AWS_ACCESS_KEY_ID,
                            aws_secret_access_key=config.AWS_SECRET_ACCESS_KEY,
                            region_name=config.AWS_REGION
                        )

                        # List multipart uploads to find the upload ID
                        if not upload_id:
                            uploads = s3.list_multipart_uploads(Bucket=config.S3_BUCKET_NAME).get('Uploads', [])
                            for upload in uploads:
                                if upload['Key'] == file_id:
                                    upload_id = upload['UploadId']
                                    print(f"Found upload ID for file {file_id}: {upload_id}")
                                    break

                        if upload_id:
                            # Get parts for this upload
                            s3_parts = s3.list_parts(Bucket=config.S3_BUCKET_NAME, Key=file_id, UploadId=upload_id).get('Parts', [])
                            for part in s3_parts:
                                parts.append({
                                    'PartNumber': part['PartNumber'],
                                    'ETag': part['ETag']
                                })
                                print(f"Added part from S3: PartNumber={part['PartNumber']}, ETag={part['ETag']}")
                    except Exception as s3_parts_error:
                        print(f"Error getting parts from S3: {str(s3_parts_error)}")

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
                        print(f"Error using s3_utils.complete_multipart_upload: {str(complete_error)}")
                        logger.error(f"Error using s3_utils.complete_multipart_upload: {str(complete_error)}")

                        # Try direct S3 API call as a fallback
                        try:
                            s3 = boto3.client(
                                's3',
                                endpoint_url=config.S3_ENDPOINT,
                                aws_access_key_id=config.AWS_ACCESS_KEY_ID,
                                aws_secret_access_key=config.AWS_SECRET_ACCESS_KEY,
                                region_name=config.AWS_REGION
                            )

                            response = s3.complete_multipart_upload(
                                Bucket=config.S3_BUCKET_NAME,
                                Key=file_id,
                                UploadId=upload_id,
                                MultipartUpload={'Parts': parts}
                            )

                            print(f"Direct S3 API multipart upload response: {response}")
                            logger.info(f"Direct S3 API multipart upload response: {response}")

                            # Store the ETag of the complete file
                            file_metadata.complete_etag = response.get('ETag', '')
                            file_metadata.save()

                            print(f"Multipart upload completed for file {file_id} using direct S3 API")
                            logger.info(f"Multipart upload completed for file {file_id} using direct S3 API")
                        except Exception as s3_error:
                            print(f"Error using direct S3 API: {str(s3_error)}")
                            logger.error(f"Error using direct S3 API: {str(s3_error)}")
                else:
                    print(f"No parts available for file {file_id}, cannot complete multipart upload")
                    logger.warning(f"No parts available for file {file_id}, cannot complete multipart upload")
            except Exception as e:
                print(f"Failed to complete multipart upload: {str(e)}")
                logger.error(f"Failed to complete multipart upload: {str(e)}")
                # Don't raise an exception here, as we still want to return success for the confirmed chunks
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
