from pydantic import BaseModel, field_validator
from typing import List, Optional, Dict, Any

class FileMetaRequest(BaseModel):
    """
    Request model for creating a file in the Files Service
    """
    file_name: str
    file_path: str
    file_type: str
    folder_id: str
    chunk_count: int
    file_hash: Optional[str] = None

    model_config = {
        "extra": "ignore"
    }

class PresignedUrlResponse(BaseModel):
    """
    Response model for a presigned URL
    """
    chunk_id: str
    presigned_url: str
    part_number: Optional[int] = None
    upload_id: Optional[str] = None

    model_config = {
        "extra": "ignore"
    }

class FileMetaResponse(BaseModel):
    """
    Response model for file creation
    """
    file_id: str
    presigned_urls: List[PresignedUrlResponse]

    model_config = {
        "extra": "ignore"
    }

class ChunkETagInfo(BaseModel):
    """
    Model for chunk ETag information
    """
    chunk_id: str
    part_number: int
    etag: str
    fingerprint: str  # Make fingerprint required

    model_config = {
        "extra": "ignore"
    }

class ChunkConfirmRequest(BaseModel):
    """
    Request model for confirming chunks
    """
    file_id: str
    chunk_ids: List[str]
    chunk_etags: Optional[List[Dict[str, Any]]] = None

    model_config = {
        "extra": "ignore"
    }

    @field_validator('chunk_etags')
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
    """
    Response model for confirming chunks
    """
    file_id: str
    confirmed_chunks: int
    success: bool

    model_config = {
        "extra": "ignore"
    }

class FolderRequest(BaseModel):
    """
    Request model for creating/updating a folder
    """
    folder_id: str
    folder_path: str
    folder_name: str
    parent_folder_id: Optional[str] = None

    model_config = {
        "extra": "ignore"
    }

class FolderResponse(BaseModel):
    """
    Response model for folder creation/update
    """
    folder_id: str
    success: bool

    model_config = {
        "extra": "ignore"
    }
