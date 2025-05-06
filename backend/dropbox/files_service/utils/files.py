"""
File-related helper functions for the Files Service.
"""
from fastapi import HTTPException
import uuid
from datetime import datetime, timezone
import logging

from models import FilesMetaData
from utils.s3 import abort_multipart_upload

logger = logging.getLogger(__name__)

def create_file_metadata(file_id, file_meta):
    """Create file metadata in DynamoDB"""
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
        return file_metadata
    except Exception as e:
        logger.error(f"Failed to create file metadata: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to create file metadata: {str(e)}")

def format_presigned_url_response(file_id, presigned_urls_data):
    """Format the response for the client"""
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

def cleanup_file_resources(file_id):
    """Clean up file resources if creation fails"""
    try:
        # Get file metadata to check if it exists
        try:
            file_metadata = FilesMetaData.get(file_id)
            upload_id = file_metadata.upload_id
            
            # Delete file metadata
            file_metadata.delete()
            
            # Abort multipart upload if it was started
            if upload_id:
                abort_multipart_upload(file_id, upload_id)
        except:
            pass
    except Exception as e:
        logger.error(f"Error cleaning up file resources: {str(e)}")
