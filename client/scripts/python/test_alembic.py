#!/usr/bin/env python3
# Test script for Alembic

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from db.models import Base, FilesMetaData, Chunks
import os

def test_db():
    # Create database engine
    engine = create_engine("sqlite:///./dropbox.db")
    
    # Create tables
    Base.metadata.create_all(engine)
    
    # Create session
    Session = sessionmaker(bind=engine)
    session = Session()
    
    # Test creating a file metadata
    file_metadata = FilesMetaData(
        file_id="test-file-id",
        folder_id="test-folder-id",
        file_type="txt"
    )
    
    # Add to session
    session.add(file_metadata)
    session.commit()
    
    # Test creating a chunk
    chunk = Chunks(
        chunk_id="test-chunk-id",
        file_id="test-file-id",
        fingerprint="test-fingerprint"
    )
    
    # Add to session
    session.add(chunk)
    session.commit()
    
    # Query and print results
    print("File Metadata:")
    for file in session.query(FilesMetaData).all():
        print(f"  {file}")
    
    print("\nChunks:")
    for chunk in session.query(Chunks).all():
        print(f"  {chunk}")
    
    # Close session
    session.close()
    
    print("\nTest completed successfully!")

if __name__ == "__main__":
    test_db()
