from sqlalchemy import Column, PrimaryKeyConstraint, String, ForeignKey, DateTime, Integer, Boolean, CheckConstraint
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
from datetime import datetime, timezone

Base = declarative_base()

class Folders(Base):
    __tablename__ = 'folders'

    folder_id = Column(String, primary_key=True)
    folder_path = Column(String, nullable=False, unique=True)  # Full path to the folder
    folder_name = Column(String, nullable=False)  # Just the folder name
    parent_folder_id = Column(String, ForeignKey('folders.folder_id'), nullable=True)  # Parent folder ID (null for root)

    # Relationships
    files = relationship("FilesMetaData", back_populates="folder", cascade="all, delete-orphan")
    subfolders = relationship("Folders",
                             backref="parent_folder",
                             remote_side=[folder_id],
                             cascade="all",
                             single_parent=True)

    def __repr__(self):
        return f"<Folders(folder_id='{self.folder_id}', folder_path='{self.folder_path}', folder_name='{self.folder_name}')>"

class FilesMetaData(Base):
    __tablename__ = 'files_metadata'

    file_id = Column(String, primary_key=True)
    file_type = Column(String, nullable=False)
    file_path = Column(String, nullable=False, unique=True)  # Full path to the file
    file_name = Column(String, nullable=False)   # Just the filename
    file_hash = Column(String, nullable=True)    # Hash for deduplication
    folder_id = Column(String, ForeignKey('folders.folder_id'), nullable=False)  # Folder containing this file
    # master_file_fingerprint removed as it's no longer needed

    # Relationships
    folder = relationship("Folders", back_populates="files")
    chunks = relationship("Chunks", back_populates="file", cascade="all, delete-orphan")

    def __repr__(self):
        return f"<FilesMetaData(file_id='{self.file_id}', file_path='{self.file_path}', file_name='{self.file_name}', file_type='{self.file_type}')>"

class Chunks(Base):
    __tablename__ = 'chunks'

    chunk_id = Column(String, nullable=False)
    file_id = Column(String, ForeignKey('files_metadata.file_id'), nullable=False)
    __table_args__ = (PrimaryKeyConstraint('chunk_id', 'file_id'),)
    part_number = Column(Integer, nullable=True)  # Part number for multipart upload
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    last_synced = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    fingerprint = Column(String, nullable=False)

    # Relationship with FilesMetaData
    file = relationship("FilesMetaData", back_populates="chunks")

    def __repr__(self):
        return f"<Chunks(chunk_id='{self.chunk_id}', file_id='{self.file_id}', part_number='{self.part_number}', created_at='{self.created_at}', last_synced='{self.last_synced}', fingerprint='{self.fingerprint}')>"


class System(Base):
    __tablename__ = 'system'

    id = Column(Integer, primary_key=True)
    system_last_sync_time = Column(String, nullable=True)

    __table_args__ = (
        CheckConstraint('id = 1', name='check_singleton_id'),
    )

    def __repr__(self):
        return f"<System(id='{self.id}', system_last_sync_time='{self.system_last_sync_time}')>"
