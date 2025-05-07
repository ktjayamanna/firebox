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
    FolderRequest, FolderResponse,
    DownloadRequest, DownloadResponse, DownloadUrlResponse
)
from utils.files import create_file_metadata, format_presigned_url_response, cleanup_file_resources
from utils.chunks import create_chunk_entries, process_etag_info, process_chunks, calculate_master_file_fingerprint
from utils.folders import get_or_create_folder
from utils.s3 import generate_and_store_presigned_urls, complete_multipart_upload_process, generate_download_urls
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
    # Use the file ID provided by the client
    file_id = file_meta.file_id

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

        # Get the master file fingerprint if available
        master_fingerprint = file_metadata.master_file_fingerprint if hasattr(file_metadata, 'master_file_fingerprint') else None

        # If master fingerprint is not available, try to calculate it
        if not master_fingerprint and confirmed_count > 0:
            master_fingerprint = calculate_master_file_fingerprint(file_id)

        return {
            "file_id": file_id,
            "confirmed_chunks": confirmed_count,
            "success": confirmed_count == len(chunk_ids),
            "master_file_fingerprint": master_fingerprint
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

@router.post("/files/download", response_model=DownloadResponse)
async def download_chunks(download_request: DownloadRequest):
    """
    Generate presigned URLs for downloading file chunks

    This endpoint:
    1. Verifies that the requested chunks exist
    2. Checks that the fingerprints match what's stored in the database
    3. Generates presigned URLs for downloading each chunk with the correct byte range
    """
    file_id = download_request.file_id
    requested_chunks = download_request.chunks

    logger.info(f"Download request for file {file_id} with {len(requested_chunks)} chunks")

    try:
        # Get all chunks for this file from DynamoDB
        _, chunk_map = get_chunks_for_file(file_id)

        if not chunk_map:
            logger.error(f"No chunks found for file {file_id}")
            return {
                "file_id": file_id,
                "download_urls": [],
                "success": False,
                "error_message": f"No chunks found for file {file_id}"
            }

        # Verify chunks and collect part numbers for valid chunks
        valid_chunks = []
        invalid_chunks = []

        for chunk_info in requested_chunks:
            chunk_id = chunk_info.chunk_id
            requested_part_number = chunk_info.part_number
            requested_fingerprint = chunk_info.fingerprint

            # Check if chunk exists in database
            if chunk_id not in chunk_map:
                logger.warning(f"Chunk {chunk_id} not found in database")
                invalid_chunks.append({
                    "chunk_id": chunk_id,
                    "reason": "Chunk not found"
                })
                continue

            # Get the chunk from the database
            chunk = chunk_map[chunk_id]

            # Verify part number matches
            if chunk.part_number != requested_part_number:
                logger.warning(f"Part number mismatch for chunk {chunk_id}: requested {requested_part_number}, stored {chunk.part_number}")
                invalid_chunks.append({
                    "chunk_id": chunk_id,
                    "reason": f"Part number mismatch: requested {requested_part_number}, stored {chunk.part_number}"
                })
                continue

            # Verify fingerprint matches
            if chunk.fingerprint != requested_fingerprint:
                logger.warning(f"Fingerprint mismatch for chunk {chunk_id}: requested {requested_fingerprint}, stored {chunk.fingerprint}")
                invalid_chunks.append({
                    "chunk_id": chunk_id,
                    "reason": "Fingerprint has changed, please try again"
                })
                continue

            # If all checks pass, add to valid chunks
            valid_chunks.append({
                "chunk_id": chunk_id,
                "part_number": chunk.part_number,
                "fingerprint": chunk.fingerprint
            })

        # If no valid chunks, return error
        if not valid_chunks:
            logger.error(f"No valid chunks found for download request")
            return {
                "file_id": file_id,
                "download_urls": [],
                "success": False,
                "error_message": "No valid chunks found for download. Fingerprints may have changed."
            }

        # Generate presigned URLs for valid chunks
        part_numbers = [chunk["part_number"] for chunk in valid_chunks]
        download_url_data = generate_download_urls(file_id, part_numbers)

        # Map the download URLs to the valid chunks
        download_urls = []
        for chunk in valid_chunks:
            # Find the corresponding URL data
            url_data = next((data for data in download_url_data if data["part_number"] == chunk["part_number"]), None)

            if url_data:
                download_urls.append({
                    "chunk_id": chunk["chunk_id"],
                    "part_number": chunk["part_number"],
                    "fingerprint": chunk["fingerprint"],
                    "presigned_url": url_data["presigned_url"],
                    "start_byte": url_data["start_byte"],
                    "end_byte": url_data["end_byte"],
                    "range_header": url_data["range_header"]
                })

        # Return the download URLs
        return {
            "file_id": file_id,
            "download_urls": download_urls,
            "success": True,
            "error_message": None if not invalid_chunks else f"{len(invalid_chunks)} chunks had errors"
        }
    except Exception as e:
        logger.error(f"Error generating download URLs: {str(e)}")
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Failed to generate download URLs: {str(e)}")
