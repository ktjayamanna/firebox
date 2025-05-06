from pynamodb.models import Model
from pynamodb.attributes import UnicodeAttribute, UTCDateTimeAttribute, NumberAttribute
from datetime import datetime, timezone
from config import DYNAMODB_HOST, DYNAMODB_REGION

class FilesMetaData(Model):
    """
    PynamoDB model for file metadata
    """
    class Meta:
        table_name = 'FilesMetaData'
        region = DYNAMODB_REGION
        host = DYNAMODB_HOST

    file_id = UnicodeAttribute(hash_key=True)
    file_type = UnicodeAttribute()
    file_path = UnicodeAttribute()
    file_name = UnicodeAttribute()
    file_hash = UnicodeAttribute(null=True)
    folder_id = UnicodeAttribute()
    upload_id = UnicodeAttribute(null=True)  # Store the multipart upload ID
    complete_etag = UnicodeAttribute(null=True)  # Store the ETag of the completed file

    def __repr__(self):
        return f"<FilesMetaData(file_id='{self.file_id}', file_path='{self.file_path}', file_name='{self.file_name}', file_type='{self.file_type}')>"

class Chunks(Model):
    """
    PynamoDB model for file chunks
    """
    class Meta:
        table_name = 'Chunks'
        region = DYNAMODB_REGION
        host = DYNAMODB_HOST

    chunk_id = UnicodeAttribute(hash_key=True)
    file_id = UnicodeAttribute(range_key=True)
    part_number = NumberAttribute(default=0)  # Part number for multipart upload
    created_at = UTCDateTimeAttribute(default=lambda: datetime.now(timezone.utc))
    last_synced = UTCDateTimeAttribute(null=True)
    fingerprint = UnicodeAttribute()
    etag = UnicodeAttribute(null=True)  # ETag returned by S3 after part upload

    def __repr__(self):
        return f"<Chunks(chunk_id='{self.chunk_id}', file_id='{self.file_id}', created_at='{self.created_at}', last_synced='{self.last_synced}', fingerprint='{self.fingerprint}')>"

class Folders(Model):
    """
    PynamoDB model for folder metadata
    """
    class Meta:
        table_name = 'Folders'
        region = DYNAMODB_REGION
        host = DYNAMODB_HOST

    folder_id = UnicodeAttribute(hash_key=True)
    folder_path = UnicodeAttribute()
    folder_name = UnicodeAttribute()
    parent_folder_id = UnicodeAttribute(null=True)  # Parent folder ID (null for root)

    def __repr__(self):
        return f"<Folders(folder_id='{self.folder_id}', folder_path='{self.folder_path}', folder_name='{self.folder_name}')>"


