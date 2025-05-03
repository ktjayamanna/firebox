from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from db.engine import get_db
from db.models import FilesMetaData, Chunks, Folders
from typing import List

router = APIRouter()

@router.get("/folders", response_model=List[dict])
def get_folders(db: Session = Depends(get_db)):
    """Get all folders"""
    folders = db.query(Folders).all()
    return [
        {
            "folder_id": folder.folder_id,
            "folder_path": folder.folder_path,
            "folder_name": folder.folder_name,
            "parent_folder_id": folder.parent_folder_id
        }
        for folder in folders
    ]

@router.get("/folders/{folder_id}", response_model=dict)
def get_folder(folder_id: str, db: Session = Depends(get_db)):
    """Get folder by ID"""
    folder = db.query(Folders).filter(Folders.folder_id == folder_id).first()
    if not folder:
        raise HTTPException(status_code=404, detail="Folder not found")
    return {
        "folder_id": folder.folder_id,
        "folder_path": folder.folder_path,
        "folder_name": folder.folder_name,
        "parent_folder_id": folder.parent_folder_id
    }

@router.get("/files", response_model=List[dict])
def get_files(db: Session = Depends(get_db)):
    """Get all files metadata"""
    files = db.query(FilesMetaData).all()
    return [
        {
            "file_id": file.file_id,
            "folder_id": file.folder_id,
            "file_path": file.file_path,
            "file_name": file.file_name,
            "file_type": file.file_type,
            "file_hash": file.file_hash
        }
        for file in files
    ]

@router.get("/files/{file_id}", response_model=dict)
def get_file(file_id: str, db: Session = Depends(get_db)):
    """Get file metadata by ID"""
    file = db.query(FilesMetaData).filter(FilesMetaData.file_id == file_id).first()
    if not file:
        raise HTTPException(status_code=404, detail="File not found")
    return {
        "file_id": file.file_id,
        "folder_id": file.folder_id,
        "file_path": file.file_path,
        "file_name": file.file_name,
        "file_type": file.file_type,
        "file_hash": file.file_hash
    }

@router.get("/chunks/{file_id}", response_model=List[dict])
def get_chunks(file_id: str, db: Session = Depends(get_db)):
    """Get all chunks for a file"""
    chunks = db.query(Chunks).filter(Chunks.file_id == file_id).all()
    return [
        {
            "chunk_id": chunk.chunk_id,
            "file_id": chunk.file_id,
            "created_at": chunk.created_at,
            "last_synced": chunk.last_synced,
            "fingerprint": chunk.fingerprint
        }
        for chunk in chunks
    ]
