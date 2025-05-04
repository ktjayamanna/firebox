import boto3
from botocore.client import Config
from typing import List, Dict
import config

def get_s3_client():
    """
    Create and return an S3 client configured for MinIO
    """
    return boto3.client(
        's3',
        endpoint_url=config.S3_ENDPOINT,
        aws_access_key_id=config.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=config.AWS_SECRET_ACCESS_KEY,
        region_name=config.AWS_REGION,
        config=Config(signature_version='s3v4'),
        verify=False,  # Disable SSL verification for local development
        use_ssl=config.S3_USE_SSL
    )

def initiate_multipart_upload(file_id: str) -> str:
    """
    Initiate a multipart upload

    Args:
        file_id: ID of the file

    Returns:
        str: Upload ID
    """
    s3_client = get_s3_client()
    object_key = file_id  # Use file_id as the object key

    response = s3_client.create_multipart_upload(
        Bucket=config.S3_BUCKET_NAME,
        Key=object_key,
        ContentType='application/octet-stream'
    )

    return response['UploadId']

def generate_presigned_urls(file_id: str, chunk_count: int) -> List[Dict[str, str]]:
    """
    Generate presigned URLs for multipart upload

    Args:
        file_id: ID of the file
        chunk_count: Number of chunks to generate URLs for

    Returns:
        List of dictionaries containing chunk_id and presigned_url
    """
    s3_client = get_s3_client()

    # Initiate multipart upload
    upload_id = initiate_multipart_upload(file_id)
    presigned_urls = []

    for i in range(chunk_count):
        chunk_id = f"{file_id}_{i}"
        part_number = i + 1  # Part numbers start at 1

        # Generate presigned URL for upload_part operation
        presigned_url = s3_client.generate_presigned_url(
            'upload_part',
            Params={
                'Bucket': config.S3_BUCKET_NAME,
                'Key': file_id,
                'UploadId': upload_id,
                'PartNumber': part_number
            },
            ExpiresIn=config.PRESIGNED_URL_EXPIRATION
        )

        presigned_urls.append({
            'chunk_id': chunk_id,
            'presigned_url': presigned_url,
            'part_number': part_number,
            'upload_id': upload_id
        })

    return presigned_urls

def complete_multipart_upload(file_id: str, upload_id: str, parts: List[Dict]) -> Dict:
    """
    Complete a multipart upload

    Args:
        file_id: ID of the file
        upload_id: ID of the multipart upload
        parts: List of dictionaries with PartNumber and ETag for each part

    Returns:
        Dict: Response from S3
    """
    s3_client = get_s3_client()

    response = s3_client.complete_multipart_upload(
        Bucket=config.S3_BUCKET_NAME,
        Key=file_id,
        UploadId=upload_id,
        MultipartUpload={
            'Parts': parts
        }
    )

    return response

def abort_multipart_upload(file_id: str, upload_id: str) -> Dict:
    """
    Abort a multipart upload

    Args:
        file_id: ID of the file
        upload_id: ID of the multipart upload

    Returns:
        Dict: Response from S3
    """
    s3_client = get_s3_client()

    response = s3_client.abort_multipart_upload(
        Bucket=config.S3_BUCKET_NAME,
        Key=file_id,
        UploadId=upload_id
    )

    return response
