from sqlalchemy.orm import Session
from db.models import FilesMetaData, Chunks, Folders, System
from datetime import datetime, timezone
import os
import uuid
import hashlib
from config import CHUNK_DIR, SYNC_DIR, CHUNK_SIZE
from typing import Optional

class SyncEngine:
    def __init__(self, db: Session, sync_dir: str = SYNC_DIR):
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

        # Check if the directory itself exists in the database
        existing_dir = self.find_existing_folder(directory_path)
        if existing_dir:
            # If the directory exists, return its ID
            return existing_dir.folder_id

        # For file paths, we need to ensure the parent directory exists
        parent_dir = os.path.dirname(directory_path)

        # If the parent is the sync directory, return the root folder ID
        if parent_dir == self.sync_dir:
            root_folder = self._get_or_create_root_folder()
            return root_folder.folder_id

        # Ensure all parent directories exist in the database
        return self._ensure_folder_tree(directory_path)

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
            print(f"Added root folder to local database: {self.sync_dir}")

            # Sync root folder with server
            try:
                from server.client import FileServiceClient
                api_client = FileServiceClient()

                # Send root folder information to server
                response = api_client.create_folder(
                    folder_id=root_id,
                    folder_path=self.sync_dir,
                    folder_name=root_name,
                    parent_folder_id=None
                )

                if response.get('success'):
                    print(f"Successfully synced root folder with server")
                else:
                    print(f"Failed to sync root folder with server: {response}")
            except Exception as e:
                print(f"Error syncing root folder with server: {e}")

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
        Create a folder in the database and sync with server

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

        # Create folder in local database
        folder = Folders(
            folder_id=folder_id,
            folder_path=folder_path,
            folder_name=folder_name,
            parent_folder_id=parent_folder_id
        )

        self.db.add(folder)
        self.db.commit()
        print(f"Added folder to local database: {folder_path}")

        # Sync folder with server
        try:
            from server.client import FileServiceClient
            api_client = FileServiceClient()

            # Send folder information to server
            response = api_client.create_folder(
                folder_id=folder_id,
                folder_path=folder_path,
                folder_name=folder_name,
                parent_folder_id=parent_folder_id
            )

            if response.get('success'):
                print(f"Successfully synced folder {folder_path} with server")
            else:
                print(f"Failed to sync folder {folder_path} with server: {response}")
        except Exception as e:
            print(f"Error syncing folder {folder_path} with server: {e}")

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
            # Sort chunks by part_number to ensure correct order
            for chunk in sorted(chunks, key=lambda x: x.part_number):
                chunk_path = os.path.join(CHUNK_DIR, f"{chunk.chunk_id}.chunk")
                print(f"Looking for chunk at: {chunk_path}")
                if os.path.exists(chunk_path):
                    print(f"Found chunk at: {chunk_path}")
                    with open(chunk_path, 'rb') as chunk_file:
                        f.write(chunk_file.read())
                else:
                    print(f"Warning: Chunk not found at {chunk_path}")
                    # Try alternative path format as fallback
                    alt_chunk_path = os.path.join(CHUNK_DIR, f"{file_id}_{chunk.part_number-1}.chunk")
                    if os.path.exists(alt_chunk_path):
                        print(f"Found chunk at alternative path: {alt_chunk_path}")
                        with open(alt_chunk_path, 'rb') as chunk_file:
                            f.write(chunk_file.read())
                    else:
                        print(f"Warning: Chunk not found at alternative path {alt_chunk_path} either")

        return True

    def update_file_location(self, old_path: str, new_path: str) -> bool:
        """
        Update a file's location in the database when it's moved or renamed

        Args:
            old_path: Original path of the file
            new_path: New path of the file

        Returns:
            bool: True if successful, False otherwise
        """
        try:
            # Find the file by its old path
            file_metadata = self.db.query(FilesMetaData).filter(
                FilesMetaData.file_path == old_path
            ).first()

            if not file_metadata:
                print(f"File not found at path {old_path}")
                return False

            # Extract new file name and parent path
            new_file_name = os.path.basename(new_path)
            new_parent_path = os.path.dirname(new_path)

            # Ensure parent directory exists in the database and get its folder_id
            new_folder_id = self.ensure_parent_directories(new_parent_path)

            # Update file metadata
            file_metadata.file_path = new_path
            file_metadata.file_name = new_file_name
            file_metadata.folder_id = new_folder_id

            # Commit changes
            self.db.commit()
            print(f"Updated file location from {old_path} to {new_path}")

            # Sync changes with server
            try:
                from server.client import FileServiceClient
                api_client = FileServiceClient()

                # Send updated file information to server
                response = api_client.update_file(
                    file_id=file_metadata.file_id,
                    file_name=new_file_name,
                    file_path=new_path,
                    folder_id=new_folder_id
                )

                if response.get('success'):
                    print(f"Successfully synced file location update with server")
                else:
                    print(f"Failed to sync file location update with server: {response}")
            except Exception as e:
                print(f"Error syncing file location update with server: {e}")

            return True

        except Exception as e:
            print(f"Error updating file location: {e}")
            self.db.rollback()
            return False

    def update_folder_location(self, old_path: str, new_path: str) -> bool:
        """
        Update a folder's location in the database when it's moved or renamed

        Args:
            old_path: Original path of the folder
            new_path: New path of the folder

        Returns:
            bool: True if successful, False otherwise
        """
        try:
            # Find the folder by its old path
            folder = self.db.query(Folders).filter(
                Folders.folder_path == old_path
            ).first()

            if not folder:
                print(f"Folder not found at path {old_path}")
                return False

            # Extract new folder name and parent path
            new_folder_name = os.path.basename(new_path)
            new_parent_path = os.path.dirname(new_path)

            # Find parent folder
            parent_folder = None
            if new_parent_path != self.sync_dir:
                parent_folder = self.db.query(Folders).filter(
                    Folders.folder_path == new_parent_path
                ).first()

                if not parent_folder:
                    # Create parent folder if it doesn't exist
                    parent_folder_id = self._ensure_folder_tree(new_parent_path)
                    parent_folder = self.db.query(Folders).filter(
                        Folders.folder_id == parent_folder_id
                    ).first()

            # Update folder metadata
            old_folder_path = folder.folder_path
            folder.folder_path = new_path
            folder.folder_name = new_folder_name
            if parent_folder:
                folder.parent_folder_id = parent_folder.folder_id
            else:
                # If no parent folder, this is a top-level folder
                root_folder = self._get_or_create_root_folder()
                folder.parent_folder_id = root_folder.folder_id

            # Update paths for all files in this folder
            files_to_update = self.db.query(FilesMetaData).filter(
                FilesMetaData.folder_id == folder.folder_id
            ).all()

            for file in files_to_update:
                # Calculate new file path
                new_file_path = file.file_path.replace(old_folder_path, new_path)

                # Update file path
                file.file_path = new_file_path

            # Update paths for all subfolders recursively
            self._update_subfolder_paths(folder.folder_id, old_folder_path, new_path)

            # Commit changes
            self.db.commit()
            print(f"Updated folder location from {old_path} to {new_path}")

            # Sync changes with server
            try:
                from server.client import FileServiceClient
                api_client = FileServiceClient()

                # Send updated folder information to server
                response = api_client.update_folder(
                    folder_id=folder.folder_id,
                    folder_name=new_folder_name,
                    folder_path=new_path,
                    parent_folder_id=folder.parent_folder_id
                )

                if response.get('success'):
                    print(f"Successfully synced folder location update with server")
                else:
                    print(f"Failed to sync folder location update with server: {response}")
            except Exception as e:
                print(f"Error syncing folder location update with server: {e}")

            return True

        except Exception as e:
            print(f"Error updating folder location: {e}")
            self.db.rollback()
            return False

    def _update_subfolder_paths(self, parent_folder_id: str, old_base_path: str, new_base_path: str):
        """
        Recursively update paths for all subfolders of a folder

        Args:
            parent_folder_id: ID of the parent folder
            old_base_path: Original base path
            new_base_path: New base path
        """
        # Get all subfolders
        subfolders = self.db.query(Folders).filter(
            Folders.parent_folder_id == parent_folder_id
        ).all()

        for subfolder in subfolders:
            # Calculate new subfolder path
            old_subfolder_path = subfolder.folder_path
            new_subfolder_path = old_subfolder_path.replace(old_base_path, new_base_path)

            # Update subfolder path
            subfolder.folder_path = new_subfolder_path

            # Update paths for all files in this subfolder
            files_to_update = self.db.query(FilesMetaData).filter(
                FilesMetaData.folder_id == subfolder.folder_id
            ).all()

            for file in files_to_update:
                # Calculate new file path
                new_file_path = file.file_path.replace(old_base_path, new_base_path)

                # Update file path
                file.file_path = new_file_path

            # Recursively update subfolders
            self._update_subfolder_paths(subfolder.folder_id, old_base_path, new_base_path)

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

    def _process_file_chunks(self, file_path: str, file_id: str, chunk_size: int = CHUNK_SIZE):
        """
        Process a file into chunks and upload to the file service

        1. Split the file into chunks
        2. Send file metadata to the file service
        3. Upload chunks using presigned URLs
        4. Confirm successful uploads

        Args:
            file_path: Path to the file to process
            file_id: ID of the file
            chunk_size: Size of each chunk in bytes (default: 5MB)
        """
        from server.client import FileServiceClient

        # Get file metadata
        file_name = os.path.basename(file_path)
        _, file_extension = os.path.splitext(file_path)
        file_type = file_extension[1:] if file_extension else "unknown"

        # Get folder ID
        file_metadata = self.db.query(FilesMetaData).filter(FilesMetaData.file_id == file_id).first()
        if not file_metadata:
            print(f"Error: File metadata not found for file ID {file_id}")
            return

        folder_id = file_metadata.folder_id
        file_hash = file_metadata.file_hash

        # First pass: count chunks and collect fingerprints
        chunk_count = 0
        fingerprints = []

        with open(file_path, 'rb') as f:
            while True:
                chunk_data = f.read(chunk_size)
                if not chunk_data:
                    break

                # Calculate fingerprint (hash) of chunk
                fingerprint = hashlib.sha256(chunk_data).hexdigest()
                fingerprints.append(fingerprint)
                chunk_count += 1

        print(f"File {file_path} will be split into {chunk_count} chunks")

        # Initialize API client
        api_client = FileServiceClient()

        try:
            # Step 1: Send file metadata to file service and get presigned URLs
            print(f"Sending file metadata to file service for {file_path}")
            response = api_client.create_file(
                file_id=file_id,  # Pass the client-generated file ID
                file_name=file_name,
                file_path=file_path,
                file_type=file_type,
                folder_id=folder_id,
                chunk_count=chunk_count,
                file_hash=file_hash
            )

            remote_file_id = response.get('file_id')
            presigned_urls = response.get('presigned_urls', [])

            if not remote_file_id or not presigned_urls:
                print(f"Error: Invalid response from file service: {response}")
                return

            print(f"Received file ID {remote_file_id} and {len(presigned_urls)} presigned URLs")

            # Step 2: Upload chunks using presigned URLs
            successful_chunk_ids = []

            with open(file_path, 'rb') as f:
                for i in range(chunk_count):
                    chunk_data = f.read(chunk_size)
                    if not chunk_data:
                        break

                    # Generate chunk ID
                    chunk_id = f"{file_id}_{i}"
                    local_chunk_id = chunk_id  # For local storage
                    remote_chunk_id = presigned_urls[i]['chunk_id']  # From API response

                    # Calculate fingerprint (hash) of chunk
                    fingerprint = hashlib.sha256(chunk_data).hexdigest()

                    # Save chunk to the dedicated chunk directory (not in sync dir)
                    chunk_path = os.path.join(CHUNK_DIR, f"{local_chunk_id}.chunk")
                    print(f"Saving chunk to: {chunk_path}")
                    try:
                        with open(chunk_path, 'wb') as chunk_file:
                            chunk_file.write(chunk_data)
                        print(f"Successfully saved chunk to {chunk_path}")
                    except Exception as e:
                        print(f"Error saving chunk to {chunk_path}: {e}")
                        continue

                    # Create local chunk metadata
                    chunk = Chunks(
                        chunk_id=local_chunk_id,
                        file_id=file_id,
                        part_number=i + 1,  # Part numbers start at 1
                        created_at=datetime.now(timezone.utc),
                        last_synced=None,  # Will be updated after successful upload
                        fingerprint=fingerprint
                    )
                    self.db.add(chunk)

                    # Upload chunk to S3 using presigned URL
                    presigned_url = presigned_urls[i]['presigned_url']
                    print(f"Uploading chunk {i+1}/{chunk_count} to S3...")

                    upload_success, etag = api_client.upload_chunk(presigned_url, chunk_data)
                    if upload_success:
                        print(f"Successfully uploaded chunk {i+1}/{chunk_count}" + (f" with ETag: {etag}" if etag else ""))

                        # Store chunk info with ETag and fingerprint
                        # Important: We must use the exact ETag returned by S3/MinIO
                        # This is critical for the multipart upload completion
                        chunk_info = {
                            'chunk_id': remote_chunk_id,
                            'part_number': i + 1,  # Part numbers start at 1
                            'etag': etag,  # Use the exact ETag from S3/MinIO
                            'fingerprint': fingerprint  # Include the SHA-256 fingerprint
                        }

                        # Only add to successful chunks if we got an ETag
                        if etag:
                            successful_chunk_ids.append(chunk_info)
                            # Update last_synced timestamp
                            chunk.last_synced = datetime.now(timezone.utc)
                        else:
                            print(f"Warning: No ETag received for chunk {i+1}/{chunk_count}, cannot complete multipart upload")
                    else:
                        print(f"Failed to upload chunk {i+1}/{chunk_count}")

            # Step 3: Confirm successful uploads
            if successful_chunk_ids:
                print(f"Confirming {len(successful_chunk_ids)} successful uploads")
                print(f"Chunk ETags: {successful_chunk_ids}")
                confirm_response = api_client.confirm_upload(remote_file_id, successful_chunk_ids)
                print(f"Confirmation response: {confirm_response}")

                # If the confirmation failed, try again with a more direct approach
                if not confirm_response.get('success', False):
                    print(f"Confirmation failed. Trying again with a more direct approach...")

                    # Create a simpler chunk_etags structure
                    simple_chunk_etags = []
                    for chunk_info in successful_chunk_ids:
                        simple_chunk_etags.append({
                            'chunk_id': chunk_info['chunk_id'],
                            'part_number': chunk_info['part_number'],
                            'etag': chunk_info['etag'],
                            'fingerprint': chunk_info.get('fingerprint', '')  # Include fingerprint if available
                        })

                    # Try again with the simpler structure
                    retry_response = api_client.confirm_upload(remote_file_id, simple_chunk_etags)
                    print(f"Retry confirmation response: {retry_response}")

                if confirm_response.get('success'):
                    print(f"Successfully confirmed {confirm_response.get('confirmed_chunks')} chunks")

                    # Update system_last_sync_time in the System table
                    try:
                        system_record = self.db.query(System).filter(System.id == 1).first()
                        if system_record:
                            current_time = datetime.now(timezone.utc).isoformat()
                            system_record.system_last_sync_time = current_time
                            self.db.commit()
                            print(f"Updated system_last_sync_time to {current_time}")
                        else:
                            print("Warning: System record not found, cannot update system_last_sync_time")
                    except Exception as e:
                        print(f"Error updating system_last_sync_time: {e}")
                else:
                    print(f"Failed to confirm uploads: {confirm_response}")
            else:
                print("No chunks were successfully uploaded")

        except Exception as e:
            print(f"Error during file upload process: {e}")

        # Commit changes to local database
        self.db.commit()

    def process_sync_response(self, sync_response):
        """
        Process the sync response from the server

        This method:
        1. Processes each updated file in the response
        2. Downloads any missing chunks
        3. Updates the local database
        4. Updates the System table with the new last_sync_time

        Args:
            sync_response: Response from the sync endpoint

        Returns:
            bool: True if sync was successful, False otherwise
        """
        from server.client import FileServiceClient
        import requests

        if not sync_response:
            print("Error: Invalid sync response")
            return False

        # Check if we're already up to date
        if sync_response.get('up_to_date', False):
            print("Already up to date with server")

            # Update system_last_sync_time in the System table
            try:
                system_record = self.db.query(System).filter(System.id == 1).first()
                if system_record:
                    system_record.system_last_sync_time = sync_response.get('last_sync_time')
                    self.db.commit()
                    print(f"Updated system_last_sync_time to {sync_response.get('last_sync_time')}")
                else:
                    print("Warning: System record not found, cannot update system_last_sync_time")
            except Exception as e:
                print(f"Error updating system_last_sync_time: {e}")

            return True

        # Process updated files
        updated_files = sync_response.get('updated_files', [])
        print(f"Processing {len(updated_files)} updated files from server")

        for file_info in updated_files:
            file_id = file_info.get('file_id')
            file_path = file_info.get('file_path')
            file_name = file_info.get('file_name')
            file_type = file_info.get('file_type')
            folder_id = file_info.get('folder_id')
            chunks = file_info.get('chunks', [])

            print(f"Processing file: {file_path} with {len(chunks)} updated chunks")

            # First try to find the file by path (most reliable)
            local_file = self.db.query(FilesMetaData).filter(FilesMetaData.file_path == file_path).first()

            # If not found by path, try by file_id as fallback
            if not local_file:
                local_file = self.db.query(FilesMetaData).filter(FilesMetaData.file_id == file_id).first()

            if not local_file:
                # Create new file metadata
                print(f"Creating new file metadata for {file_path}")
                local_file = FilesMetaData(
                    file_id=file_id,
                    file_type=file_type,
                    file_path=file_path,
                    folder_id=folder_id,
                    file_name=file_name
                )
                self.db.add(local_file)
                self.db.commit()

                # Ensure parent directories exist
                parent_dir = os.path.dirname(file_path)
                self.ensure_parent_directories(parent_dir)
            else:
                # File already exists, no need to update metadata
                print(f"File metadata already exists for {file_path}")

            # Process chunks
            for chunk_info in chunks:
                chunk_id = chunk_info.get('chunk_id')
                part_number = chunk_info.get('part_number')
                fingerprint = chunk_info.get('fingerprint')
                created_at = chunk_info.get('created_at')

                # First, try to find the chunk by file_id and part_number (most reliable)
                local_chunk = self.db.query(Chunks).filter(
                    Chunks.file_id == file_id,
                    Chunks.part_number == part_number
                ).first()

                # If not found by part_number, try by chunk_id as fallback
                if not local_chunk:
                    local_chunk = self.db.query(Chunks).filter(
                        Chunks.chunk_id == chunk_id,
                        Chunks.file_id == file_id
                    ).first()

                if local_chunk:
                    # Check if fingerprint matches (this is the key comparison)
                    if local_chunk.fingerprint == fingerprint:
                        print(f"Chunk for file {file_id}, part {part_number} already exists with matching fingerprint")
                        continue
                    else:
                        print(f"Chunk for file {file_id}, part {part_number} exists but fingerprint has changed, downloading new version")
                        # Delete existing chunk
                        self.db.delete(local_chunk)
                        self.db.commit()

                # Download chunk from server
                print(f"Downloading chunk {chunk_id} for file {file_id}")

                # Create a download request for this chunk
                api_client = FileServiceClient()
                download_request = {
                    "file_id": file_id,
                    "chunks": [
                        {
                            "chunk_id": chunk_id,
                            "part_number": part_number,
                            "fingerprint": fingerprint
                        }
                    ]
                }

                try:
                    # Call the download endpoint
                    download_response = api_client._make_request("POST", "/files/download", download_request)

                    if not download_response.get('success', False):
                        print(f"Error downloading chunk {chunk_id}: {download_response.get('error_message')}")
                        continue

                    # Get the download URL
                    download_urls = download_response.get('download_urls', [])
                    if not download_urls:
                        print(f"No download URLs returned for chunk {chunk_id}")
                        continue

                    download_url = download_urls[0].get('presigned_url')

                    # Download the chunk
                    response = requests.get(download_url, timeout=60)
                    response.raise_for_status()

                    # Save the chunk to the chunk directory
                    chunk_path = os.path.join(CHUNK_DIR, f"{chunk_id}.chunk")
                    with open(chunk_path, 'wb') as f:
                        f.write(response.content)

                    # Create chunk metadata
                    new_chunk = Chunks(
                        chunk_id=chunk_id,
                        file_id=file_id,
                        part_number=part_number,
                        created_at=datetime.fromisoformat(created_at.replace('Z', '+00:00')),
                        last_synced=datetime.now(timezone.utc),
                        fingerprint=fingerprint
                    )
                    self.db.add(new_chunk)
                    self.db.commit()

                    print(f"Successfully downloaded and saved chunk {chunk_id}")

                except Exception as e:
                    print(f"Error downloading chunk {chunk_id}: {e}")
                    continue

            # Check if we need to reconstruct the file
            local_chunks = self.db.query(Chunks).filter(Chunks.file_id == file_id).all()
            if local_chunks:
                # Reconstruct the file
                print(f"Reconstructing file {file_path}")

                # Ensure the directory exists
                os.makedirs(os.path.dirname(file_path), exist_ok=True)

                # Reconstruct the file from chunks
                with open(file_path, 'wb') as f:
                    # Sort chunks by part_number to ensure correct order
                    for chunk in sorted(local_chunks, key=lambda x: x.part_number):
                        chunk_path = os.path.join(CHUNK_DIR, f"{chunk.chunk_id}.chunk")
                        if os.path.exists(chunk_path):
                            with open(chunk_path, 'rb') as chunk_file:
                                f.write(chunk_file.read())
                        else:
                            print(f"Warning: Chunk not found at {chunk_path}")
                            # Try alternative path format as fallback
                            alt_chunk_path = os.path.join(CHUNK_DIR, f"{file_id}_{chunk.part_number-1}.chunk")
                            if os.path.exists(alt_chunk_path):
                                print(f"Found chunk at alternative path: {alt_chunk_path}")
                                with open(alt_chunk_path, 'rb') as chunk_file:
                                    f.write(chunk_file.read())
                            else:
                                print(f"Warning: Chunk not found at alternative path {alt_chunk_path} either")

                print(f"Successfully reconstructed file {file_path}")

        # Update system_last_sync_time in the System table
        try:
            system_record = self.db.query(System).filter(System.id == 1).first()
            if system_record:
                system_record.system_last_sync_time = sync_response.get('last_sync_time')
                self.db.commit()
                print(f"Updated system_last_sync_time to {sync_response.get('last_sync_time')}")
            else:
                print("Warning: System record not found, cannot update system_last_sync_time")
        except Exception as e:
            print(f"Error updating system_last_sync_time: {e}")

        return True
