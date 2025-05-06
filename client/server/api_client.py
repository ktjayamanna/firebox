import requests
import os
import logging
from typing import List, Dict, Optional, Tuple
from config import FILES_SERVICE_URL, REQUEST_TIMEOUT, MAX_RETRIES
import time
from server.schema import (
    FileMetaRequest, FileMetaResponse, ChunkETagInfo,
    ChunkConfirmRequest, ChunkConfirmResponse, FolderRequest, FolderResponse
)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class FileServiceClient:
    """
    Client for interacting with the Files Service API
    """
    def __init__(self, base_url: str = FILES_SERVICE_URL, timeout: int = REQUEST_TIMEOUT, max_retries: int = MAX_RETRIES):
        """
        Initialize the client

        Args:
            base_url: Base URL of the Files Service API
            timeout: Request timeout in seconds
            max_retries: Maximum number of retries for failed requests
        """
        self.base_url = base_url
        self.timeout = timeout
        self.max_retries = max_retries
        self.session = requests.Session()

    def _make_request(self, method: str, endpoint: str, data: Optional[Dict] = None,
                     files: Optional[Dict] = None, retry_count: int = 0) -> Dict:
        """
        Make an HTTP request to the Files Service API with retry logic

        Args:
            method: HTTP method (GET, POST, etc.)
            endpoint: API endpoint
            data: Request data
            files: Files to upload
            retry_count: Current retry count

        Returns:
            Dict: Response data that can be parsed into the appropriate Pydantic model
        """
        url = f"{self.base_url}{endpoint}"

        try:
            if method == "GET":
                response = self.session.get(url, params=data, timeout=self.timeout)
            elif method == "POST":
                response = self.session.post(url, json=data, files=files, timeout=self.timeout)
            else:
                raise ValueError(f"Unsupported HTTP method: {method}")

            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            if retry_count < self.max_retries:
                # Exponential backoff
                wait_time = 2 ** retry_count
                logger.warning(f"Request failed: {e}. Retrying in {wait_time} seconds...")
                time.sleep(wait_time)
                return self._make_request(method, endpoint, data, files, retry_count + 1)
            else:
                logger.error(f"Request failed after {self.max_retries} retries: {e}")
                raise

    def create_file(self, file_name: str, file_path: str, file_type: str,
                   folder_id: str, chunk_count: int, file_hash: str) -> FileMetaResponse:
        """
        Create a file in the Files Service and get presigned URLs for uploading chunks

        Args:
            file_name: Name of the file
            file_path: Path of the file
            file_type: Type of the file
            folder_id: ID of the folder containing the file
            chunk_count: Number of chunks
            file_hash: Hash of the file

        Returns:
            FileMetaResponse: Response containing file_id and presigned_urls
        """
        # Create a FileMetaRequest object
        file_meta_request = FileMetaRequest(
            file_name=file_name,
            file_path=file_path,
            file_type=file_type,
            folder_id=folder_id,
            chunk_count=chunk_count,
            file_hash=file_hash
        )

        # Convert to dict for the API request
        data = file_meta_request.model_dump()

        logger.info(f"Creating file metadata for {file_path} with {chunk_count} chunks")
        return self._make_request("POST", "/files", data)

    def upload_chunk(self, presigned_url: str, chunk_data: bytes) -> Tuple[bool, Optional[str]]:
        """
        Upload a chunk using a presigned URL

        Args:
            presigned_url: Presigned URL for uploading the chunk
            chunk_data: Chunk data to upload

        Returns:
            Tuple[bool, Optional[str]]: (success, etag) - success is True if upload was successful,
                                        and etag is the ETag returned by S3
        """
        try:
            # Presigned URLs require a direct PUT request, not through our _make_request method
            response = requests.put(presigned_url, data=chunk_data, timeout=self.timeout)
            response.raise_for_status()

            # Extract the ETag from the response headers
            etag = response.headers.get('ETag')
            if etag:
                # Log the raw ETag for debugging
                print(f"DEBUG: Raw ETag from S3/MinIO: '{etag}'")
                logger.info(f"DEBUG: Raw ETag from S3/MinIO: '{etag}'")

                # S3/MinIO typically returns ETags with quotes, which we should preserve
                # Just remove any extra whitespace
                etag = etag.strip()

                # Log the processed ETag
                print(f"DEBUG: Processed ETag: '{etag}'")
                logger.info(f"DEBUG: Processed ETag: '{etag}'")

                logger.info(f"Chunk uploaded successfully with ETag: {etag}")
                return True, etag
            else:
                logger.warning("Chunk uploaded but no ETag was returned")
                return True, None
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to upload chunk: {e}")
            return False, None

    def create_folder(self, folder_id: str, folder_path: str, folder_name: str, parent_folder_id: Optional[str] = None) -> FolderResponse:
        """
        Create or update a folder in the Files Service

        Args:
            folder_id: ID of the folder
            folder_path: Path of the folder
            folder_name: Name of the folder
            parent_folder_id: ID of the parent folder (None for root)

        Returns:
            FolderResponse: Response data
        """
        # Create a FolderRequest object
        folder_request = FolderRequest(
            folder_id=folder_id,
            folder_path=folder_path,
            folder_name=folder_name,
            parent_folder_id=parent_folder_id
        )

        # Convert to dict for the API request
        data = folder_request.model_dump()

        logger.info(f"Creating/updating folder {folder_name} with ID {folder_id}")
        return self._make_request("POST", "/folders", data)

    def confirm_upload(self, file_id: str, chunk_data: List[Dict[str, str]]) -> ChunkConfirmResponse:
        """
        Confirm successful upload of chunks

        Args:
            file_id: ID of the file
            chunk_data: List of dictionaries containing chunk_id, part_number, etag, and fingerprint for each chunk

        Returns:
            ChunkConfirmResponse: Response data
        """
        # Extract just the chunk IDs for backward compatibility
        chunk_ids = [chunk['chunk_id'] for chunk in chunk_data]

        # Print detailed information about the chunk data
        print(f"Confirming upload for file {file_id} with {len(chunk_ids)} chunks")

        # Create a copy of chunk_data to avoid modifying the original
        processed_chunk_data = []

        for i, chunk in enumerate(chunk_data):
            # Create a copy of the chunk data
            processed_chunk = chunk.copy()

            # Ensure each chunk has a fingerprint (SHA-256 hash)
            if 'fingerprint' not in processed_chunk:
                # This should not happen if the client is properly calculating fingerprints
                # But as a fallback, we'll use a placeholder
                logger.warning(f"Chunk {processed_chunk['chunk_id']} missing fingerprint, using placeholder")
                processed_chunk['fingerprint'] = "placeholder-fingerprint-" + processed_chunk['chunk_id']

            # Handle ETag quotes - S3 returns ETags with quotes, and we need to preserve them
            # for the CompleteMultipartUpload call
            if 'etag' in processed_chunk:
                # Log the raw ETag
                print(f"DEBUG: Raw ETag for chunk {processed_chunk['chunk_id']}: '{processed_chunk['etag']}'")

                # Ensure the ETag has quotes (S3 expects them)
                etag_value = processed_chunk['etag']
                if not (etag_value.startswith('"') and etag_value.endswith('"')):
                    etag_value = etag_value.strip('"')
                    etag_value = f'"{etag_value}"'
                    processed_chunk['etag'] = etag_value
                    print(f"DEBUG: Added quotes to ETag: '{etag_value}'")

            print(f"  Chunk {i+1}: chunk_id={processed_chunk['chunk_id']}, part_number={processed_chunk['part_number']}, etag={processed_chunk['etag']}, fingerprint={processed_chunk['fingerprint']}")
            processed_chunk_data.append(processed_chunk)

        # Create a ChunkConfirmRequest object
        chunk_confirm_request = ChunkConfirmRequest(
            file_id=file_id,
            chunk_ids=chunk_ids,
            chunk_etags=processed_chunk_data  # Include the processed chunk data with ETags and fingerprints
        )

        # Convert to dict for the API request
        data = chunk_confirm_request.model_dump()

        logger.info(f"Confirming upload for file {file_id} with {len(chunk_ids)} chunks")
        logger.info(f"Full confirmation data: {data}")

        # Make the request
        print(f"Sending confirmation request to /files/confirm with data: {data}")
        response = self._make_request("POST", "/files/confirm", data)
        print(f"Confirmation response: {response}")
        logger.info(f"Confirmation response: {response}")
        return response
