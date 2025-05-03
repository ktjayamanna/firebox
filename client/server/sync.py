from sqlalchemy.orm import Session
from sqlalchemy import func
from db.models import FilesMetaData, Chunks
from datetime import datetime, timezone
import os
import uuid
import hashlib
from config import CHUNK_DIR, SYNC_DIR
from typing import Optional, List, Dict, Set, Tuple

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

    def upload_file(self, file_path: str) -> str:
        """
        Upload a file to the sync directory and create metadata
        If the file already exists at the same path, update it instead of creating a new entry

        Args:
            file_path: Path to the file to upload

        Returns:
            file_id: ID of the uploaded file
        """
        # Normalize the file path to ensure consistent path format
        file_path = os.path.normpath(file_path)

        # Extract file name and parent path
        file_name = os.path.basename(file_path)
        parent_path = os.path.dirname(file_path)

        # Ensure parent directory exists in the database
        self.ensure_parent_directories(parent_path)

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
            existing_file.parent_path = parent_path
            existing_file.file_name = file_name
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
                file_type=file_type,
                file_path=file_path,
                parent_path=parent_path,
                file_name=file_name,
                file_hash=file_hash
            )
            self.db.add(file_metadata)
            self.db.commit()

            # Process file chunks for new file
            self._process_file_chunks(file_path, file_id)

        return file_id

    def ensure_parent_directories(self, directory_path: str) -> None:
        """
        Ensure that all parent directories in the path are tracked in the database

        Args:
            directory_path: Path to the directory
        """
        # Skip if this is the sync directory itself
        if directory_path == self.sync_dir or not directory_path.startswith(self.sync_dir):
            return

        # Get all parent directories that need to be created
        parts = os.path.relpath(directory_path, self.sync_dir).split(os.sep)
        current_path = self.sync_dir

        for part in parts:
            if not part:  # Skip empty parts
                continue

            current_path = os.path.join(current_path, part)

            # Check if this directory is already in the database
            existing_dir = self.db.query(FilesMetaData).filter(
                FilesMetaData.file_path == current_path,
                FilesMetaData.file_type == "directory"
            ).first()

            if not existing_dir:
                # Create directory entry
                dir_id = str(uuid.uuid4())
                parent_path = os.path.dirname(current_path)
                dir_name = os.path.basename(current_path)

                dir_metadata = FilesMetaData(
                    file_id=dir_id,
                    file_type="directory",
                    file_path=current_path,
                    parent_path=parent_path,
                    file_name=dir_name,
                    file_hash=None  # Directories don't have content hashes
                )

                self.db.add(dir_metadata)
                print(f"Added directory to database: {current_path}")

        self.db.commit()

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
        Scan the sync directory for files and directories and process any that aren't already in the database
        """
        print(f"Scanning sync directory: {self.sync_dir}")

        # Track statistics
        file_count = 0
        dir_count = 0
        processed_count = 0
        skipped_count = 0

        # First, ensure the root sync directory is in the database
        root_dir = self.db.query(FilesMetaData).filter(
            FilesMetaData.file_path == self.sync_dir,
            FilesMetaData.file_type == "directory"
        ).first()

        if not root_dir:
            # Create root directory entry
            dir_id = str(uuid.uuid4())
            dir_name = os.path.basename(self.sync_dir)
            parent_path = os.path.dirname(self.sync_dir)

            root_dir = FilesMetaData(
                file_id=dir_id,
                file_type="directory",
                file_path=self.sync_dir,
                parent_path=parent_path,
                file_name=dir_name,
                file_hash=None
            )

            self.db.add(root_dir)
            self.db.commit()
            print(f"Added root directory to database: {self.sync_dir}")
            dir_count += 1

        # Process all directories and files
        for root, dirs, files in os.walk(self.sync_dir):
            # Process directories first
            for dirname in dirs:
                dir_path = os.path.join(root, dirname)

                # Skip hidden directories
                if dirname.startswith('.'):
                    continue

                # Ensure directory is in the database
                existing_dir = self.db.query(FilesMetaData).filter(
                    FilesMetaData.file_path == dir_path,
                    FilesMetaData.file_type == "directory"
                ).first()

                if not existing_dir:
                    # Create directory entry
                    dir_id = str(uuid.uuid4())
                    parent_path = os.path.dirname(dir_path)

                    dir_metadata = FilesMetaData(
                        file_id=dir_id,
                        file_type="directory",
                        file_path=dir_path,
                        parent_path=parent_path,
                        file_name=dirname,
                        file_hash=None
                    )

                    self.db.add(dir_metadata)
                    print(f"Added directory to database: {dir_path}")
                    dir_count += 1

            # Process files
            for filename in files:
                file_path = os.path.join(root, filename)

                # Skip hidden files
                if filename.startswith('.'):
                    continue

                file_count += 1

                # Process the file
                try:
                    # Check if file already exists at this path
                    existing_file = self.find_existing_file(file_path, None)

                    if existing_file and existing_file.file_hash:
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

        # Commit any remaining changes
        self.db.commit()

        print(f"Scan complete. Found {file_count} files and {dir_count} directories.")
        print(f"Processed {processed_count} files, skipped {skipped_count} unchanged files.")

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
