"""
Database-related helper functions for the Files Service.
"""
from fastapi import HTTPException
import logging

from models import FilesMetaData, Chunks, Folders

logger = logging.getLogger(__name__)

def create_tables():
    """Create DynamoDB tables if they don't exist"""
    if not FilesMetaData.exists():
        FilesMetaData.create_table(read_capacity_units=5, write_capacity_units=5, wait=True)
        print("Created FilesMetaData table")

    if not Chunks.exists():
        Chunks.create_table(read_capacity_units=5, write_capacity_units=5, wait=True)
        print("Created Chunks table")

    if not Folders.exists():
        Folders.create_table(read_capacity_units=5, write_capacity_units=5, wait=True)
        print("Created Folders table")

def get_file_metadata(file_id):
    """Get file metadata and verify upload ID exists"""
    try:
        file_metadata = FilesMetaData.get(file_id)
        upload_id = file_metadata.upload_id
        logger.info(f"Found file metadata with upload_id: {upload_id}")

        if not upload_id:
            logger.error(f"No active multipart upload found for file {file_id}")
            raise HTTPException(status_code=400, detail=f"No active multipart upload found for file {file_id}")

        return file_metadata, upload_id
    except Exception as e:
        logger.error(f"Error getting file metadata: {str(e)}")
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=404, detail=f"File with ID {file_id} not found")

def get_chunks_for_file(file_id):
    """Get all chunks for a file"""
    try:
        # Use scan with filter to find all chunks for this file
        all_chunks = list(Chunks.scan(Chunks.file_id == file_id))
        print(f"Found {len(all_chunks)} chunks for file {file_id} using scan")
        logger.info(f"Found {len(all_chunks)} chunks for file {file_id} using scan")

        # Create a map of chunk_id to chunk object for easier lookup
        chunk_map = {chunk.chunk_id: chunk for chunk in all_chunks}

        return all_chunks, chunk_map
    except Exception as e:
        logger.error(f"Error getting chunks for file: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error getting chunks for file: {str(e)}")
