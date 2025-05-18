from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from db.engine import get_db
from db.models import FilesMetaData, Chunks, Folders, System
from typing import List, Dict, Any
from datetime import datetime, timezone
from server.schema import FileMetadata, ChunkMetadata, FolderMetadata, SystemInfo, SyncResponse
from server.client import FileServiceClient
from server.sync import SyncEngine

router = APIRouter()

@router.get("/folders", response_model=List[FolderMetadata])
def get_folders(db: Session = Depends(get_db)):
    """Get all folders"""
    folders = db.query(Folders).all()
    return [
        FolderMetadata(
            folder_id=folder.folder_id,
            folder_path=folder.folder_path,
            folder_name=folder.folder_name,
            parent_folder_id=folder.parent_folder_id
        )
        for folder in folders
    ]

@router.get("/folders/{folder_id}", response_model=FolderMetadata)
def get_folder(folder_id: str, db: Session = Depends(get_db)):
    """Get folder by ID"""
    folder = db.query(Folders).filter(Folders.folder_id == folder_id).first()
    if not folder:
        raise HTTPException(status_code=404, detail="Folder not found")
    return FolderMetadata(
        folder_id=folder.folder_id,
        folder_path=folder.folder_path,
        folder_name=folder.folder_name,
        parent_folder_id=folder.parent_folder_id
    )

@router.get("/files", response_model=List[FileMetadata])
def get_files(db: Session = Depends(get_db)):
    """Get all files metadata"""
    files = db.query(FilesMetaData).all()
    return [
        FileMetadata(
            file_id=file.file_id,
            folder_id=file.folder_id,
            file_path=file.file_path,
            file_name=file.file_name,
            file_type=file.file_type,
            file_hash=file.file_hash
        )
        for file in files
    ]

@router.get("/files/{file_id}", response_model=FileMetadata)
def get_file(file_id: str, db: Session = Depends(get_db)):
    """Get file metadata by ID"""
    file = db.query(FilesMetaData).filter(FilesMetaData.file_id == file_id).first()
    if not file:
        raise HTTPException(status_code=404, detail="File not found")
    return FileMetadata(
        file_id=file.file_id,
        folder_id=file.folder_id,
        file_path=file.file_path,
        file_name=file.file_name,
        file_type=file.file_type,
        file_hash=file.file_hash
    )

@router.get("/chunks/{file_id}", response_model=List[ChunkMetadata])
def get_chunks(file_id: str, db: Session = Depends(get_db)):
    """Get all chunks for a file"""
    chunks = db.query(Chunks).filter(Chunks.file_id == file_id).all()
    return [
        ChunkMetadata(
            chunk_id=chunk.chunk_id,
            file_id=chunk.file_id,
            created_at=chunk.created_at,
            last_synced=chunk.last_synced,
            fingerprint=chunk.fingerprint
        )
        for chunk in chunks
    ]

@router.get("/system", response_model=SystemInfo)
def get_system_info(db: Session = Depends(get_db)):
    """Get system information including last sync time"""
    system = db.query(System).filter(System.id == 1).first()
    if not system:
        raise HTTPException(status_code=404, detail="System information not found")
    return SystemInfo(
        id=system.id,
        system_last_sync_time=system.system_last_sync_time
    )

@router.post("/sync", response_model=SyncResponse)
def sync_with_server(db: Session = Depends(get_db)):
    """
    Sync with the server to get updates since the last sync time

    This endpoint is called periodically (every 2 minutes) by the client to poll for changes.
    It:
    1. Gets the last sync time from the System table
    2. Calls the server sync endpoint
    3. Updates the last sync time in the System table
    4. Returns the sync response to the client
    """
    # Get the last sync time from the System table
    system = db.query(System).filter(System.id == 1).first()
    if not system:
        raise HTTPException(status_code=404, detail="System information not found")

    last_sync_time = system.system_last_sync_time
    if not last_sync_time:
        # If no last sync time, use a default (e.g., epoch)
        last_sync_time = "1970-01-01T00:00:00+00:00"

    # Create a client to call the server
    client = FileServiceClient()

    try:
        # Call the server sync endpoint
        response = client.sync(last_sync_time)

        # Process the sync response using the SyncEngine
        sync_engine = SyncEngine(db)
        success = sync_engine.process_sync_response(response)

        if not success:
            raise HTTPException(status_code=500, detail="Failed to process sync response")

        return response
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to sync with server: {str(e)}")
