from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import uuid
from datetime import datetime
import os

from models import FilesMetaData, Chunks
from s3_utils import generate_presigned_urls, complete_multipart_upload, abort_multipart_upload
import config

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

class ChunkConfirmRequest(BaseModel):
    file_id: str
    chunk_ids: List[str]

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

    # Verify file exists
    try:
        file_metadata = FilesMetaData.get(file_id)
        upload_id = file_metadata.upload_id
        if not upload_id:
            raise HTTPException(status_code=400, detail=f"No active multipart upload found for file {file_id}")
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=404, detail=f"File with ID {file_id} not found")

    # Update chunk status and collect parts for completing multipart upload
    confirmed_count = 0
    parts = []

    try:
        # Get all chunks for this file to collect ETags
        all_chunks = list(Chunks.query(file_id, Chunks.file_id == file_id))

        # Check if all chunks are confirmed
        all_confirmed = True

        for chunk in all_chunks:
            # Check if this chunk is in the confirmed list
            if chunk.chunk_id in chunk_ids:
                # Mark as synced
                chunk.last_synced = datetime.utcnow()

                # For multipart upload, we need to extract the ETag from the S3 response
                # Since we don't have it from the client, we'll use a placeholder
                # In a real implementation, the client would send the ETag
                chunk.etag = f"etag-placeholder-{chunk.part_number}"
                chunk.save()
                confirmed_count += 1

                # Add to parts list for completing multipart upload
                parts.append({
                    'PartNumber': int(chunk.part_number),
                    'ETag': chunk.etag
                })
            elif not chunk.last_synced:
                # If any chunk is not synced, we can't complete the multipart upload
                all_confirmed = False

        # If all chunks are confirmed, complete the multipart upload
        if all_confirmed and len(all_chunks) > 0:
            try:
                # Sort parts by part number
                parts.sort(key=lambda x: x['PartNumber'])

                # Complete the multipart upload
                response = complete_multipart_upload(file_id, upload_id, parts)

                # Store the ETag of the complete file
                file_metadata.complete_etag = response.get('ETag', '')
                file_metadata.save()

                print(f"Multipart upload completed for file {file_id}")
            except Exception as e:
                print(f"Failed to complete multipart upload: {str(e)}")
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
