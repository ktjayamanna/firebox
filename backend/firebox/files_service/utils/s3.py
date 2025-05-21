"""
S3/MinIO-related helper functions for the Files Service.
"""
from fastapi import HTTPException
import logging
import json
import boto3
from botocore.client import Config
from typing import List, Dict, Optional
import config
from utils.chunks import update_master_file_fingerprint

logger = logging.getLogger(__name__)

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

    # Log the parts for debugging
    print(f"DEBUG: Parts for completing multipart upload: {parts}")

    # Check if ETags have quotes
    for i, part in enumerate(parts):
        etag = part.get('ETag', '')
        has_quotes = etag.startswith('"') and etag.endswith('"')
        print(f"DEBUG: Part {i+1} ETag: '{etag}', has quotes: {has_quotes}")

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

def generate_and_store_presigned_urls(file_id, chunk_count, file_metadata):
    """Generate presigned URLs and store upload ID"""
    try:
        presigned_urls_data = generate_presigned_urls(file_id, chunk_count)

        # Get the upload ID from the first presigned URL (all have the same upload ID)
        upload_id = presigned_urls_data[0]['upload_id'] if presigned_urls_data else None

        # Store the upload ID in the file metadata
        file_metadata.upload_id = upload_id
        file_metadata.save()

        return presigned_urls_data, upload_id
    except Exception as e:
        logger.error(f"Failed to generate presigned URLs: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to generate presigned URLs: {str(e)}")

def complete_multipart_upload_process(file_id, upload_id, parts, file_metadata):
    """Complete the multipart upload"""
    if len(parts) == 0:
        print(f"No parts available for file {file_id}, cannot complete multipart upload")
        logger.warning(f"No parts available for file {file_id}, cannot complete multipart upload")
        return False

    # Sort parts by part number
    parts.sort(key=lambda x: x['PartNumber'])

    print(f"Completing multipart upload for file {file_id} with {len(parts)} parts")
    print(f"Parts: {parts}")
    logger.info(f"Completing multipart upload for file {file_id} with {len(parts)} parts")
    logger.info(f"Parts: {parts}")

    # Complete the multipart upload
    try:
        # Use the s3_utils helper
        response = complete_multipart_upload(file_id, upload_id, parts)
        print(f"Multipart upload response: {response}")
        logger.info(f"Multipart upload response: {response}")

        # Store the ETag of the complete file
        file_metadata.complete_etag = response.get('ETag', '')
        file_metadata.save()

        # Calculate and store the master file fingerprint
        print(f"Calculating master file fingerprint for file {file_id}")
        logger.info(f"Calculating master file fingerprint for file {file_id}")
        update_result = update_master_file_fingerprint(file_id)

        if update_result:
            print(f"Successfully updated master file fingerprint for file {file_id}")
            logger.info(f"Successfully updated master file fingerprint for file {file_id}")
        else:
            print(f"Failed to update master file fingerprint for file {file_id}")
            logger.warning(f"Failed to update master file fingerprint for file {file_id}")

        print(f"Multipart upload completed for file {file_id}")
        logger.info(f"Multipart upload completed for file {file_id}")
        return True
    except Exception as complete_error:
        print(f"Error completing multipart upload: {str(complete_error)}")
        logger.error(f"Error completing multipart upload: {str(complete_error)}")
        raise HTTPException(status_code=500, detail=f"Error completing multipart upload: {str(complete_error)}")

def generate_download_url(file_id: str, part_number: int, chunk_size: int = config.CHUNK_SIZE) -> Dict[str, str]:
    """
    Generate a presigned URL for downloading a specific byte range of a file

    Args:
        file_id: ID of the file
        part_number: Part number (1-based)
        chunk_size: Size of each chunk in bytes (default: 5MB)

    Returns:
        Dict containing the presigned URL and byte range information
    """
    s3_client = get_s3_client()

    # Calculate byte range based on part number and chunk size
    # Part numbers are 1-based, so we subtract 1 when calculating the start position
    start_byte = (part_number - 1) * chunk_size
    end_byte = (part_number * chunk_size) - 1  # End byte is inclusive

    # Generate presigned URL for get_object operation
    # Note: We don't include the Range header in the presigned URL parameters
    # The client will need to add this header when making the request
    presigned_url = s3_client.generate_presigned_url(
        'get_object',
        Params={
            'Bucket': config.S3_BUCKET_NAME,
            'Key': file_id,
            'ResponseContentType': 'application/octet-stream',
            'ResponseContentDisposition': f'attachment; filename="{file_id}_part{part_number}"'
        },
        ExpiresIn=config.PRESIGNED_URL_EXPIRATION
    )

    # Log the byte range for debugging
    logger.info(f"Generated download URL for part {part_number} with byte range: {start_byte}-{end_byte}")

    return {
        'presigned_url': presigned_url,
        'start_byte': start_byte,
        'end_byte': end_byte,
        'range_header': f'bytes={start_byte}-{end_byte}'
    }

def generate_download_urls(file_id: str, part_numbers: List[int], chunk_size: int = config.CHUNK_SIZE) -> List[Dict[str, str]]:
    """
    Generate presigned URLs for downloading specific parts of a file

    Args:
        file_id: ID of the file
        part_numbers: List of part numbers to generate URLs for
        chunk_size: Size of each chunk in bytes (default: 5MB)

    Returns:
        List of dictionaries containing presigned URLs and byte ranges
    """
    download_urls = []

    for part_number in part_numbers:
        try:
            url_data = generate_download_url(file_id, part_number, chunk_size)
            download_urls.append({
                'part_number': part_number,
                'presigned_url': url_data['presigned_url'],
                'start_byte': url_data['start_byte'],
                'end_byte': url_data['end_byte'],
                'range_header': url_data['range_header']
            })
        except Exception as e:
            logger.error(f"Failed to generate download URL for part {part_number}: {str(e)}")
            # Continue with other parts even if one fails

    return download_urls
