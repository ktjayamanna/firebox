import requests
import os
import logging
from typing import List, Dict, Optional, Tuple
from config import FILES_SERVICE_URL, REQUEST_TIMEOUT, MAX_RETRIES
import time

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
            Dict: Response data
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
                   folder_id: str, chunk_count: int, file_hash: str) -> Dict:
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
            Dict: Response containing file_id and presigned_urls
        """
        data = {
            "file_name": file_name,
            "file_path": file_path,
            "file_type": file_type,
            "folder_id": folder_id,
            "chunk_count": chunk_count,
            "file_hash": file_hash
        }

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
                # Keep the quotes for the ETag as MinIO expects them in the CompleteMultipartUpload call
                # Just remove any extra whitespace
                etag = etag.strip()
                logger.info(f"Chunk uploaded successfully with ETag: {etag}")
                return True, etag
            else:
                logger.warning("Chunk uploaded but no ETag was returned")
                return True, None
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to upload chunk: {e}")
            return False, None

    def confirm_upload(self, file_id: str, chunk_data: List[Dict[str, str]]) -> Dict:
        """
        Confirm successful upload of chunks

        Args:
            file_id: ID of the file
            chunk_data: List of dictionaries containing chunk_id, part_number, etag, and fingerprint for each chunk

        Returns:
            Dict: Response data
        """
        # Extract just the chunk IDs for backward compatibility
        chunk_ids = [chunk['chunk_id'] for chunk in chunk_data]

        # Print detailed information about the chunk data
        print(f"Confirming upload for file {file_id} with {len(chunk_ids)} chunks")
        for i, chunk in enumerate(chunk_data):
            # Ensure each chunk has a fingerprint (SHA-256 hash)
            if 'fingerprint' not in chunk:
                # This should not happen if the client is properly calculating fingerprints
                # But as a fallback, we'll use a placeholder
                logger.warning(f"Chunk {chunk['chunk_id']} missing fingerprint, using placeholder")
                chunk['fingerprint'] = "placeholder-fingerprint-" + chunk['chunk_id']

            print(f"  Chunk {i+1}: chunk_id={chunk['chunk_id']}, part_number={chunk['part_number']}, etag={chunk['etag']}, fingerprint={chunk['fingerprint']}")

        data = {
            "file_id": file_id,
            "chunk_ids": chunk_ids,
            "chunk_etags": chunk_data  # Include the full chunk data with ETags and fingerprints
        }

        logger.info(f"Confirming upload for file {file_id} with {len(chunk_ids)} chunks")
        logger.info(f"Full confirmation data: {data}")

        # Make the request
        print(f"Sending confirmation request to /files/confirm with data: {data}")
        response = self._make_request("POST", "/files/confirm", data)
        print(f"Confirmation response: {response}")
        logger.info(f"Confirmation response: {response}")
        return response
