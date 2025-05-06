"""
API endpoints for the Files Service.
"""
from fastapi import APIRouter, HTTPException
import uuid
import logging
import json

from schema import (
    FileMetaRequest, FileMetaResponse,
    ChunkConfirmRequest, ChunkConfirmResponse,
    FolderRequest, FolderResponse
)
from utils.files import create_file_metadata, format_presigned_url_response, cleanup_file_resources
from utils.chunks import create_chunk_entries, process_etag_info, process_chunks
from utils.folders import get_or_create_folder
from utils.s3 import generate_and_store_presigned_urls, complete_multipart_upload_process
from utils.db import get_file_metadata, get_chunks_for_file

logger = logging.getLogger(__name__)

router = APIRouter()

@router.get("/health")
def health_check():
    """Health check endpoint"""
    return {"status": "healthy"}

@router.post("/files", response_model=FileMetaResponse)
async def create_file(file_meta: FileMetaRequest):
    """
    Receive file metadata and generate presigned URLs for multipart upload
    """
    # Generate a unique file ID
    file_id = str(uuid.uuid4())
    
    try:
        # Create file metadata
        file_metadata = create_file_metadata(file_id, file_meta)
        
        # Generate presigned URLs
        presigned_urls_data, upload_id = generate_and_store_presigned_urls(file_id, file_meta.chunk_count, file_metadata)
        
        # Create chunk entries
        create_chunk_entries(file_id, presigned_urls_data)
        
        # Format and return response
        return format_presigned_url_response(file_id, presigned_urls_data)
    except Exception as e:
        # If any step fails, clean up and abort
        cleanup_file_resources(file_id)
        
        # Re-raise the original exception
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Failed to create file: {str(e)}")

@router.post("/files/confirm", response_model=ChunkConfirmResponse)
async def confirm_chunks(confirm_request: ChunkConfirmRequest):
    """
    Confirm successful multipart upload and update chunk status
    """
    file_id = confirm_request.file_id
    chunk_ids = confirm_request.chunk_ids

    # Print to stdout for immediate visibility in logs
    print(f"Confirming chunks for file {file_id}: {chunk_ids}")
    logger.info(f"Confirming chunks for file {file_id}: {chunk_ids}")
    logger.info(f"Chunk ETags data: {confirm_request.chunk_etags}")

    try:
        # Verify file exists and get metadata
        file_metadata, upload_id = get_file_metadata(file_id)
        
        # Process ETags from the request
        etag_map = process_etag_info(confirm_request.chunk_etags)
        
        # Debug dump of etag_map
        print(f"ETAG_MAP DUMP: {json.dumps(etag_map, indent=2)}")
        logger.info(f"ETAG_MAP DUMP: {json.dumps(etag_map, indent=2)}")
        print(f"CHUNK_IDS WE'RE LOOKING FOR: {chunk_ids}")
        logger.info(f"CHUNK_IDS WE'RE LOOKING FOR: {chunk_ids}")
        
        # Get all chunks for this file
        _, chunk_map = get_chunks_for_file(file_id)
        
        # Process chunks and update with ETags
        confirmed_count, parts = process_chunks(file_id, chunk_ids, etag_map, chunk_map)
        
        # Log the final parts list
        print(f"FINAL PARTS LIST: {json.dumps(parts, indent=2)}")
        logger.info(f"FINAL PARTS LIST: {json.dumps(parts, indent=2)}")
        print(f"CONFIRMED COUNT: {confirmed_count} out of {len(chunk_ids)} requested")
        logger.info(f"CONFIRMED COUNT: {confirmed_count} out of {len(chunk_ids)} requested")
        
        # Complete the multipart upload if we have parts
        if parts:
            complete_multipart_upload_process(file_id, upload_id, parts, file_metadata)
        
        return {
            "file_id": file_id,
            "confirmed_chunks": confirmed_count,
            "success": confirmed_count == len(chunk_ids)
        }
    except Exception as e:
        logger.error(f"Error confirming chunks: {str(e)}")
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Failed to confirm chunks: {str(e)}")

@router.post("/folders", response_model=FolderResponse)
async def create_folder(folder_request: FolderRequest):
    """
    Create or update a folder in the database
    """
    folder_id = folder_request.folder_id
    
    try:
        # Get or create folder
        return get_or_create_folder(folder_id, folder_request)
    except Exception as e:
        logger.error(f"Error creating/updating folder: {str(e)}")
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Failed to create/update folder: {str(e)}")
