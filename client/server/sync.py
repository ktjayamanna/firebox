from sqlalchemy.orm import Session
from db.models import FilesMetaData, Chunks
from datetime import datetime, timezone
import os
import uuid
import hashlib
from config import CHUNK_DIR
from typing import Optional

class SyncEngine:
    def __init__(self, db: Session, sync_dir: str = "/app/my_dropbox"):
        self.db = db
        self.sync_dir = sync_dir

        # Ensure chunk directory exists
        os.makedirs(CHUNK_DIR, exist_ok=True)

    def calculate_file_hash(self, file_path: str) -> str:
        """
        Calculate a hash for the entire file for deduplication purposes

        Args:
            file_path: Path to the file

        Returns:
            str: Hash of the file
        """
        hash_obj = hashlib.sha256()
        with open(file_path, 'rb') as f:
            # Read in chunks to handle large files efficiently
            for chunk in iter(lambda: f.read(4096), b''):
                hash_obj.update(chunk)
        return hash_obj.hexdigest()

    def find_existing_file(self, file_path: str, file_hash: str) -> Optional[FilesMetaData]:
        """
        Check if a file with the same path already exists

        Args:
            file_path: Path to the file
            file_hash: Hash of the file (not used for finding, only for updating)

        Returns:
            Optional[FilesMetaData]: Existing file metadata if found, None otherwise
        """
        # Only find by exact path match - this ensures:
        # 1. Same content in different locations = different files
        # 2. Different filenames at same path = different files
        existing_file = self.db.query(FilesMetaData).filter(
            FilesMetaData.file_path == file_path
        ).first()

        return existing_file

    def upload_file(self, file_path: str, folder_id: str = None) -> str:
        """
        Upload a file to the sync directory and create metadata
        If the file already exists at the same path, update it instead of creating a new entry

        Args:
            file_path: Path to the file to upload
            folder_id: ID of the folder to upload to (optional)

        Returns:
            file_id: ID of the uploaded file
        """
        # Normalize the file path to ensure consistent path format
        file_path = os.path.normpath(file_path)

        # Calculate file hash for content tracking
        file_hash = self.calculate_file_hash(file_path)

        # Check if file already exists at this exact path
        existing_file = self.find_existing_file(file_path, file_hash)

        # Get file type from extension
        _, file_extension = os.path.splitext(file_path)
        file_type = file_extension[1:] if file_extension else "unknown"

        if existing_file:
            # Update existing file at this path
            print(f"File already exists at path {file_path} with ID: {existing_file.file_id}. Updating...")
            file_id = existing_file.file_id

            # Update metadata if needed
            existing_file.file_type = file_type
            existing_file.folder_id = folder_id or existing_file.folder_id
            existing_file.file_hash = file_hash

            # Check if content has changed by comparing hash
            if existing_file.file_hash != file_hash:
                print(f"File content has changed. Updating chunks...")
                # Delete existing chunks only if content has changed
                self.db.query(Chunks).filter(Chunks.file_id == file_id).delete()
                self.db.commit()

                # Process new file chunks
                self._process_file_chunks(file_path, file_id)
            else:
                print(f"File content unchanged. Skipping chunk processing.")
        else:
            # Create new file metadata for this path
            file_id = str(uuid.uuid4())
            file_metadata = FilesMetaData(
                file_id=file_id,
                folder_id=folder_id,
                file_type=file_type,
                file_path=file_path,
                file_hash=file_hash
            )
            self.db.add(file_metadata)
            self.db.commit()

            # Process file chunks for new file
            self._process_file_chunks(file_path, file_id)

        return file_id

    def download_file(self, file_id: str, destination_path: str) -> bool:
        """
        Download a file from the sync directory

        Args:
            file_id: ID of the file to download
            destination_path: Path to save the downloaded file

        Returns:
            bool: True if download was successful, False otherwise
        """
        # Get file metadata
        file_metadata = self.db.query(FilesMetaData).filter(FilesMetaData.file_id == file_id).first()
        if not file_metadata:
            return False

        # Get file chunks
        chunks = self.db.query(Chunks).filter(Chunks.file_id == file_id).order_by(Chunks.chunk_id).all()
        if not chunks:
            return False

        # Reassemble file from chunks stored in the chunk directory
        print(f"Reassembling file from chunks in {CHUNK_DIR}")
        with open(destination_path, 'wb') as f:
            for chunk in chunks:
                chunk_path = os.path.join(CHUNK_DIR, f"{chunk.chunk_id}.chunk")
                print(f"Looking for chunk at: {chunk_path}")
                if os.path.exists(chunk_path):
                    print(f"Found chunk at: {chunk_path}")
                    with open(chunk_path, 'rb') as chunk_file:
                        f.write(chunk_file.read())
                else:
                    print(f"Warning: Chunk not found at {chunk_path}")

        return True

    def scan_sync_directory(self):
        """
        Scan the sync directory for files and process any that aren't already in the database
        """
        print(f"Scanning sync directory: {self.sync_dir}")

        # Get list of files in sync directory
        file_count = 0
        processed_count = 0
        skipped_count = 0

        for root, _, files in os.walk(self.sync_dir):
            for filename in files:
                file_path = os.path.join(root, filename)

                # Skip hidden files and directories
                if os.path.basename(file_path).startswith('.'):
                    continue

                file_count += 1

                # Process the file
                try:
                    # Check if file already exists at this path
                    existing_file = self.find_existing_file(file_path, None)

                    if existing_file:
                        # Calculate hash to check if content has changed
                        current_hash = self.calculate_file_hash(file_path)

                        if existing_file.file_hash == current_hash:
                            print(f"Skipping unchanged file: {file_path}")
                            skipped_count += 1
                            continue

                    # Process the file (either new or changed)
                    file_id = self.upload_file(file_path)
                    print(f"Processed file: {file_path} with ID: {file_id}")
                    processed_count += 1
                except Exception as e:
                    print(f"Error processing file {file_path}: {e}")

        print(f"Scan complete. Found {file_count} files. Processed {processed_count}, skipped {skipped_count}.")

    def _process_file_chunks(self, file_path: str, file_id: str, chunk_size: int = 5 * 1024 * 1024):
        """
        Process a file into chunks

        Args:
            file_path: Path to the file to process
            file_id: ID of the file
            chunk_size: Size of each chunk in bytes (default: 5MB)
        """
        with open(file_path, 'rb') as f:
            chunk_index = 0
            while True:
                chunk_data = f.read(chunk_size)
                if not chunk_data:
                    break

                # Generate chunk ID
                chunk_id = f"{file_id}_{chunk_index}"

                # Calculate fingerprint (hash) of chunk
                fingerprint = hashlib.sha256(chunk_data).hexdigest()

                # Save chunk to the dedicated chunk directory (not in sync dir)
                chunk_path = os.path.join(CHUNK_DIR, f"{chunk_id}.chunk")
                print(f"Saving chunk to: {chunk_path}")
                try:
                    with open(chunk_path, 'wb') as chunk_file:
                        chunk_file.write(chunk_data)
                    print(f"Successfully saved chunk to {chunk_path}")
                except Exception as e:
                    print(f"Error saving chunk to {chunk_path}: {e}")

                # Create chunk metadata
                chunk = Chunks(
                    chunk_id=chunk_id,
                    file_id=file_id,
                    created_at=datetime.now(timezone.utc),
                    last_synced=datetime.now(timezone.utc),
                    fingerprint=fingerprint
                )

                self.db.add(chunk)
                chunk_index += 1

        self.db.commit()
