from sqlalchemy.orm import Session
from sqlalchemy import func
from db.models import FilesMetaData, Chunks, Folders
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

    def find_existing_file(self, file_path: str, file_hash: str = None) -> Optional[FilesMetaData]:
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

    def cleanup_orphaned_chunks(self):
        """
        Clean up orphaned chunks that are no longer associated with any file
        """
        print("Cleaning up orphaned chunks...")

        # Get all chunk IDs from the database
        db_chunks = self.db.query(Chunks.chunk_id).all()
        db_chunk_ids = set([chunk[0] for chunk in db_chunks])

        # Get all chunk files from the chunk directory
        chunk_files = []
        if os.path.exists(CHUNK_DIR):
            chunk_files = [f for f in os.listdir(CHUNK_DIR) if f.endswith('.chunk')]

        # Find orphaned chunk files (files that exist on disk but not in the database)
        orphaned_count = 0
        for chunk_file in chunk_files:
            chunk_id = chunk_file.replace('.chunk', '')
            if chunk_id not in db_chunk_ids:
                # This is an orphaned chunk, delete it
                chunk_path = os.path.join(CHUNK_DIR, chunk_file)
                try:
                    os.remove(chunk_path)
                    print(f"Deleted orphaned chunk: {chunk_path}")
                    orphaned_count += 1
                except Exception as e:
                    print(f"Error deleting orphaned chunk {chunk_path}: {e}")

        print(f"Cleanup complete. Deleted {orphaned_count} orphaned chunks.")

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

        # Ensure parent directory exists in the database and get its folder_id
        folder_id = self.ensure_parent_directories(parent_path)

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

            # Save the old hash for comparison
            old_hash = existing_file.file_hash

            # Update metadata if needed
            existing_file.file_type = file_type
            existing_file.folder_id = folder_id
            existing_file.file_name = file_name
            existing_file.file_hash = file_hash
            self.db.commit()

            # Check if content has changed by comparing hash
            if old_hash != file_hash:
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
                folder_id=folder_id,
                file_name=file_name,
                file_hash=file_hash
            )
            self.db.add(file_metadata)
            self.db.commit()

            # Process file chunks for new file
            self._process_file_chunks(file_path, file_id)

        return file_id

    def find_existing_folder(self, folder_path: str) -> Optional[Folders]:
        """
        Check if a folder with the same path already exists

        Args:
            folder_path: Path to the folder

        Returns:
            Optional[Folders]: Existing folder if found, None otherwise
        """
        existing_folder = self.db.query(Folders).filter(
            Folders.folder_path == folder_path
        ).first()

        return existing_folder

    def ensure_parent_directories(self, directory_path: str) -> str:
        """
        Ensure that all parent directories in the path are tracked in the database

        Args:
            directory_path: Path to the directory

        Returns:
            str: Folder ID of the parent directory
        """
        # Skip if this is the sync directory itself or not within it
        if directory_path == self.sync_dir or not directory_path.startswith(self.sync_dir):
            # Return the root folder ID
            root_folder = self._get_or_create_root_folder()
            return root_folder.folder_id

        # For file paths, we need to ensure the parent directory exists
        parent_dir = os.path.dirname(directory_path)

        # If the parent is the sync directory, return the root folder ID
        if parent_dir == self.sync_dir:
            root_folder = self._get_or_create_root_folder()
            return root_folder.folder_id

        # Ensure all parent directories exist in the database
        return self._ensure_folder_tree(parent_dir)

    def _get_or_create_root_folder(self) -> Folders:
        """
        Get or create the root folder (sync directory)

        Returns:
            Folders: Root folder
        """
        root_folder = self.db.query(Folders).filter(
            Folders.folder_path == self.sync_dir
        ).first()

        if not root_folder:
            # Create root folder
            root_id = str(uuid.uuid4())
            root_name = os.path.basename(self.sync_dir)

            # Create the physical directory if it doesn't exist
            if not os.path.exists(self.sync_dir):
                os.makedirs(self.sync_dir, exist_ok=True)
                print(f"Created physical directory: {self.sync_dir}")

            root_folder = Folders(
                folder_id=root_id,
                folder_path=self.sync_dir,
                folder_name=root_name,
                parent_folder_id=None  # Root has no parent
            )

            self.db.add(root_folder)
            self.db.commit()
            print(f"Added root folder to database: {self.sync_dir}")

        return root_folder

    def _ensure_folder_tree(self, folder_path: str) -> str:
        """
        Recursively ensure that a folder and all its parent folders exist in the database

        Args:
            folder_path: Path to the folder

        Returns:
            str: Folder ID of the created/existing folder
        """
        # Skip if this is the sync directory itself
        if folder_path == self.sync_dir:
            root_folder = self._get_or_create_root_folder()
            return root_folder.folder_id

        # Check if folder already exists
        existing_folder = self.find_existing_folder(folder_path)
        if existing_folder:
            return existing_folder.folder_id

        # Ensure parent folder exists first (recursive)
        parent_dir = os.path.dirname(folder_path)
        if parent_dir == self.sync_dir:
            parent_folder_id = self._get_or_create_root_folder().folder_id
        else:
            parent_folder_id = self._ensure_folder_tree(parent_dir)

        # Now create this folder in the database
        return self._create_folder_in_db(folder_path, parent_folder_id)

    def _create_folder_in_db(self, folder_path: str, parent_folder_id: str) -> str:
        """
        Create a folder in the database

        Args:
            folder_path: Path to the folder
            parent_folder_id: ID of the parent folder

        Returns:
            str: Folder ID of the created folder
        """
        # Create folder entry
        folder_id = str(uuid.uuid4())
        folder_name = os.path.basename(folder_path)

        # Create the physical directory if it doesn't exist
        if not os.path.exists(folder_path):
            os.makedirs(folder_path, exist_ok=True)
            print(f"Created physical directory: {folder_path}")

        folder = Folders(
            folder_id=folder_id,
            folder_path=folder_path,
            folder_name=folder_name,
            parent_folder_id=parent_folder_id
        )

        self.db.add(folder)
        self.db.commit()
        print(f"Added folder to database: {folder_path}")

        return folder_id

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

        # Ensure root folder exists
        root_folder = self._get_or_create_root_folder()
        dir_count += 1

        # Process all directories and files
        for root, dirs, files in os.walk(self.sync_dir):
            # Process directories
            for dirname in dirs:
                dir_path = os.path.join(root, dirname)

                # Skip hidden directories
                if dirname.startswith('.'):
                    continue

                # Process this directory and ensure it's in the database
                folder_id = self._ensure_folder_tree(dir_path)
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

        # Clean up orphaned chunks
        self.cleanup_orphaned_chunks()

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
