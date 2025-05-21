"""
Chunk-related helper functions for the Files Service.
"""
from fastapi import HTTPException
from datetime import datetime, timezone
import logging
import json
import traceback
import hashlib

from models import Chunks, FilesMetaData
from utils.db import get_chunks_for_file

logger = logging.getLogger(__name__)

def create_chunk_entries(file_id, presigned_urls_data):
    """Create chunk entries in DynamoDB"""
    try:
        for url_data in presigned_urls_data:
            chunk_id = url_data['chunk_id']
            part_number = url_data['part_number']

            chunk = Chunks(
                chunk_id=chunk_id,
                file_id=file_id,
                part_number=part_number,
                created_at=datetime.now(timezone.utc),
                last_synced=None,
                etag=None,
                fingerprint=""  # Will be updated when chunk is uploaded
            )
            chunk.save()
        return True
    except Exception as e:
        logger.error(f"Failed to create chunk entries: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to create chunk entries: {str(e)}")

def process_etag_info(chunk_etags):
    """Process chunk ETags from the request"""
    etag_map = {}
    if not chunk_etags:
        return etag_map

    logger.info(f"Processing {len(chunk_etags)} chunk ETags from request")
    for chunk_info in chunk_etags:
        # Handle both object and dictionary formats
        chunk_id = chunk_info.get('chunk_id') if isinstance(chunk_info, dict) else chunk_info.chunk_id
        part_number = chunk_info.get('part_number') if isinstance(chunk_info, dict) else chunk_info.part_number
        etag = chunk_info.get('etag') if isinstance(chunk_info, dict) else chunk_info.etag
        fingerprint = chunk_info.get('fingerprint', '') if isinstance(chunk_info, dict) else getattr(chunk_info, 'fingerprint', '')

        # Check if fingerprint is missing or empty
        if not fingerprint:
            error_msg = f"ERROR: Missing required fingerprint for chunk {chunk_id}"
            print(error_msg)
            logger.error(error_msg)

            # Set a placeholder fingerprint for debugging
            fingerprint = f"MISSING-FINGERPRINT-{chunk_id}"
            print(f"Using placeholder fingerprint: {fingerprint}")
            logger.warning(f"Using placeholder fingerprint: {fingerprint}")

        # Log the raw ETag and fingerprint values for debugging
        print(f"Raw ETag from client for chunk {chunk_id}: '{etag}'")
        print(f"Raw fingerprint from client for chunk {chunk_id}: '{fingerprint}'")
        logger.info(f"Raw ETag from client for chunk {chunk_id}: '{etag}'")
        logger.info(f"Raw fingerprint from client for chunk {chunk_id}: '{fingerprint}'")

        etag_map[chunk_id] = {
            'part_number': part_number,
            'etag': etag,
            'fingerprint': fingerprint
        }
        logger.info(f"Added chunk info for {chunk_id}: part_number={part_number}, etag={etag}, fingerprint={fingerprint}")

    return etag_map

def update_chunk_with_etag(chunk, etag_info):
    """Update a chunk with ETag and fingerprint"""
    try:
        etag_value = etag_info['etag']
        fingerprint_value = etag_info.get('fingerprint', '')

        print(f"DEBUG: Raw ETag from client for chunk {chunk.chunk_id}: '{etag_value}'")
        logger.info(f"DEBUG: Raw ETag from client for chunk {chunk.chunk_id}: '{etag_value}'")

        # Check if ETag has quotes
        has_quotes = etag_value.startswith('"') and etag_value.endswith('"')
        print(f"DEBUG: ETag has quotes: {has_quotes}")
        logger.info(f"DEBUG: ETag has quotes: {has_quotes}")

        print(f"USING CLIENT ETAG for chunk {chunk.chunk_id}: '{etag_value}'")
        logger.info(f"USING CLIENT ETAG for chunk {chunk.chunk_id}: '{etag_value}'")

        print(f"USING FINGERPRINT for chunk {chunk.chunk_id}: '{fingerprint_value}'")
        logger.info(f"USING FINGERPRINT for chunk {chunk.chunk_id}: '{fingerprint_value}'")

        # Update chunk with ETag and fingerprint
        chunk.etag = etag_value
        chunk.fingerprint = fingerprint_value
        chunk.last_synced = datetime.now(timezone.utc)

        print(f"ATTEMPTING TO SAVE CHUNK {chunk.chunk_id} with etag={etag_value}, fingerprint={fingerprint_value}")
        logger.info(f"ATTEMPTING TO SAVE CHUNK {chunk.chunk_id} with etag={etag_value}, fingerprint={fingerprint_value}")

        # Save with exception details
        try:
            chunk.save()
            print(f"SAVE SUCCESSFUL for chunk {chunk.chunk_id}")
            logger.info(f"SAVE SUCCESSFUL for chunk {chunk.chunk_id}")
        except Exception as save_error:
            print(f"SAVE FAILED for chunk {chunk.chunk_id}: {str(save_error)}")
            logger.error(f"SAVE FAILED for chunk {chunk.chunk_id}: {str(save_error)}")
            # Log the full exception traceback
            print(f"SAVE ERROR TRACEBACK: {traceback.format_exc()}")
            logger.error(f"SAVE ERROR TRACEBACK: {traceback.format_exc()}")
            raise save_error

        # Prepare part info for completing multipart upload
        # Ensure ETag has quotes for S3/MinIO
        if not (etag_value.startswith('"') and etag_value.endswith('"')):
            etag_value = etag_value.strip('"')
            etag_value = f'"{etag_value}"'
            print(f"DEBUG: Added quotes to ETag for S3: '{etag_value}'")
            logger.info(f"DEBUG: Added quotes to ETag for S3: '{etag_value}'")

        part_info = {
            'PartNumber': int(chunk.part_number),
            'ETag': etag_value
        }

        print(f"ADDED TO PARTS LIST: PartNumber={chunk.part_number}, ETag={etag_value}")
        logger.info(f"ADDED TO PARTS LIST: PartNumber={chunk.part_number}, ETag={etag_value}")

        return part_info
    except Exception as e:
        print(f"UPDATE FAILED for chunk {chunk.chunk_id}: {str(e)}")
        logger.error(f"UPDATE FAILED for chunk {chunk.chunk_id}: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to update chunk: {str(e)}")

def calculate_master_file_fingerprint(file_id):
    """
    Calculate the master file fingerprint from all chunk fingerprints

    Args:
        file_id: ID of the file

    Returns:
        str: SHA256 hash of all chunk fingerprints concatenated in part_number order
    """
    try:
        # Get all chunks for this file
        all_chunks, _ = get_chunks_for_file(file_id)

        if not all_chunks:
            logger.warning(f"No chunks found for file {file_id}, cannot calculate master fingerprint")
            return None

        # Sort chunks by part number to ensure consistent order
        sorted_chunks = sorted(all_chunks, key=lambda x: x.part_number)

        # Concatenate all fingerprints
        fingerprints = [chunk.fingerprint for chunk in sorted_chunks]
        concatenated_fingerprints = ''.join(fingerprints)

        # Calculate SHA256 hash of the concatenated fingerprints
        master_fingerprint = hashlib.sha256(concatenated_fingerprints.encode()).hexdigest()

        print(f"Calculated master file fingerprint for file {file_id}: {master_fingerprint}")
        logger.info(f"Calculated master file fingerprint for file {file_id}: {master_fingerprint}")

        return master_fingerprint
    except Exception as e:
        print(f"Error calculating master file fingerprint: {str(e)}")
        logger.error(f"Error calculating master file fingerprint: {str(e)}")
        return None

def update_master_file_fingerprint(file_id):
    """
    Update the master file fingerprint in the file metadata

    Args:
        file_id: ID of the file

    Returns:
        bool: True if successful, False otherwise
    """
    try:
        # Calculate the master file fingerprint
        master_fingerprint = calculate_master_file_fingerprint(file_id)

        if not master_fingerprint:
            logger.warning(f"Could not calculate master fingerprint for file {file_id}")
            return False

        # Get the file metadata
        try:
            file_metadata = FilesMetaData.get(file_id)
        except Exception as e:
            logger.error(f"Error getting file metadata: {str(e)}")
            return False

        # Update the master file fingerprint
        file_metadata.master_file_fingerprint = master_fingerprint
        file_metadata.save()

        print(f"Updated master file fingerprint for file {file_id}: {master_fingerprint}")
        logger.info(f"Updated master file fingerprint for file {file_id}: {master_fingerprint}")

        return True
    except Exception as e:
        print(f"Error updating master file fingerprint: {str(e)}")
        logger.error(f"Error updating master file fingerprint: {str(e)}")
        return False

def process_chunks(file_id, chunk_ids, etag_map, chunk_map):
    """Process all chunks and update with ETags"""
    confirmed_count = 0
    parts = []

    for chunk_id in chunk_ids:
        # Check if the chunk exists in our map
        if chunk_id in chunk_map:
            chunk = chunk_map[chunk_id]
            print(f"Found chunk {chunk_id} in database")
            logger.info(f"Found chunk {chunk_id} in database")
        else:
            print(f"Chunk {chunk_id} not found in database, creating it")
            logger.info(f"Chunk {chunk_id} not found in database, creating it")

            # If the chunk doesn't exist, create it
            if chunk_id in etag_map:
                chunk_info = etag_map[chunk_id]
                chunk = Chunks(
                    chunk_id=chunk_id,
                    file_id=file_id,
                    part_number=chunk_info['part_number'],
                    created_at=datetime.now(timezone.utc),
                    fingerprint=chunk_info['fingerprint'],
                    etag=chunk_info['etag']
                )
                chunk.save()
                print(f"Created chunk {chunk_id} in database")
                logger.info(f"Created chunk {chunk_id} in database")
            else:
                print(f"No info available for chunk {chunk_id}, skipping")
                logger.warning(f"No info available for chunk {chunk_id}, skipping")
                continue

        # Use ETag from client if available
        if chunk_id in etag_map:
            try:
                part_info = update_chunk_with_etag(chunk, etag_map[chunk_id])
                parts.append(part_info)
                confirmed_count += 1
            except Exception as e:
                logger.error(f"Error updating chunk {chunk_id}: {str(e)}")
                continue
        else:
            print(f"No ETag info available for chunk {chunk_id}, skipping")
            logger.warning(f"No ETag info available for chunk {chunk_id}, skipping")

    return confirmed_count, parts
