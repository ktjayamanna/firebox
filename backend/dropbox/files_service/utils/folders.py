"""
Folder-related helper functions for the Files Service.
"""
from fastapi import HTTPException
import logging

from models import Folders

logger = logging.getLogger(__name__)

def get_or_create_folder(folder_id, folder_request):
    """Get existing folder or create a new one"""
    try:
        # Check if folder already exists
        try:
            existing_folder = Folders.get(folder_id)
            logger.info(f"Updating existing folder with ID: {folder_id}")

            # Update folder attributes
            existing_folder.folder_path = folder_request.folder_path
            existing_folder.folder_name = folder_request.folder_name
            existing_folder.parent_folder_id = folder_request.parent_folder_id
            existing_folder.save()

            return {
                "folder_id": folder_id,
                "success": True
            }
        except Folders.DoesNotExist:
            # Create new folder
            logger.info(f"Creating new folder with ID: {folder_id}")

            folder = Folders(
                folder_id=folder_id,
                folder_path=folder_request.folder_path,
                folder_name=folder_request.folder_name,
                parent_folder_id=folder_request.parent_folder_id
            )
            folder.save()

            return {
                "folder_id": folder_id,
                "success": True
            }
    except Exception as e:
        logger.error(f"Error creating/updating folder: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to create/update folder: {str(e)}")
