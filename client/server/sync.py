from sqlalchemy.orm import Session
from db.models import FilesMetaData, Chunks
from datetime import datetime, timezone
import os
import uuid
import hashlib

class SyncEngine:
    def __init__(self, db: Session, sync_dir: str = "/app/my_dropbox"):
        self.db = db
        self.sync_dir = sync_dir

    def upload_file(self, file_path: str, folder_id: str = None) -> str:
        """
        Upload a file to the sync directory and create metadata

        Args:
            file_path: Path to the file to upload
            folder_id: ID of the folder to upload to (optional)

        Returns:
            file_id: ID of the uploaded file
        """
        # Generate a unique file ID
        file_id = str(uuid.uuid4())

        # Get file type from extension
        _, file_extension = os.path.splitext(file_path)
        file_type = file_extension[1:] if file_extension else "unknown"

        # Create file metadata
        file_metadata = FilesMetaData(
            file_id=file_id,
            folder_id=folder_id,
            file_type=file_type
        )

        self.db.add(file_metadata)
        self.db.commit()

        # Process file chunks
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

        # Reassemble file from chunks
        with open(destination_path, 'wb') as f:
            for chunk in chunks:
                chunk_path = os.path.join(self.sync_dir, f"{chunk.chunk_id}.chunk")
                if os.path.exists(chunk_path):
                    with open(chunk_path, 'rb') as chunk_file:
                        f.write(chunk_file.read())

        return True

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

                # Save chunk to disk
                chunk_path = os.path.join(self.sync_dir, f"{chunk_id}.chunk")
                with open(chunk_path, 'wb') as chunk_file:
                    chunk_file.write(chunk_data)

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
