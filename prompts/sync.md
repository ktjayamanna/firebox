# Sync Feature Implementation

## Before: 

Now we are going to add an endpoint called sync where clients can poll every two seconds if the remote has changed! The way you evaluate that is that sync pollendpoint requires last sync time from the system table in sql lite. then the sync can compare that with the chunk table in dynamodb to identify what chunks have been created after the client's last sync. If no chunks are new just send up to date signal to client and client do nothing. If there are chunks, then sync end point should return file_id, file_path, chunk ids of that file, and finger prints of all the chunks. Client then, check if the file_path of the updated file on remote exists in the local db (remember that file id won't catch this, only file path will). If it exists, the query for the existing chunks of this file and then compare which chunks are out dated. Then, use the download request DownloadRequest to get the presigned urls for the new chunks, download them, and then reo the chunking process you already do when a file is added to the sync folder. Only difference this time is that you do not chunk the file. Instead you download new chunks from the remote, and then reuse the ones that have not changed, and use them all to reconstruct the file. You have to update the local db and sync status just like you would do when you add a file to the sync folder.This process is delta syncing so that clients do not have to download the entire file again. Since the upload file mechanism is tested to be working follow that implementation as much you can; there are subtle differences because this tiem you are not chunking the file, but rather downloading the chunks and then using them to reconstruct the file.Notice that,this prceess is a polling that happens every two mins by each device (client). Use the same ids on local devices as well as remote. But do not rely on it. Instead use fingerprint to recognize the chunks and file path for files and flders.


## After:

## Overview
Implement a file synchronization mechanism between client devices and the server that efficiently transfers only changed chunks of files, ensuring data consistency across multiple devices.

## Server-Side Implementation

### Sync Endpoint
1. Create a `/sync` endpoint that accepts a client's last sync timestamp
2. Compare the client's timestamp with the server's chunk table to identify chunks created or modified after the client's last sync
3. If no new/modified chunks exist, return `{"up_to_date": true, "last_sync_time": <current_server_time>}`
4. If changes exist, return:
   ```json
   {
     "up_to_date": false,
     "last_sync_time": "<current_server_time>",
     "updated_files": [
       {
         "file_id": "<file_id>",
         "file_path": "<file_path>",
         "file_name": "<file_name>",
         "file_type": "<file_type>",
         "folder_id": "<folder_id>",
         "chunks": [
           {
             "chunk_id": "<chunk_id>",
             "part_number": <part_number>,
             "fingerprint": "<sha256_hash>",
             "created_at": "<timestamp>"
           },
           ...
         ]
       },
       ...
     ]
   }
   ```

## Client-Side Implementation

### Sync Process
1. Implement a background process that polls the server every 2 minutes
2. Send the client's last sync time (from the System table) to the server
3. Process the server's response:

#### For Up-to-Date Response
- Update the client's last sync time in the System table

#### For Files Needing Update
For each file in the response:
1. Check if the file exists in the local database by file_path (primary) or file_id (fallback)
2. If the file doesn't exist locally:
   - Create file metadata in the local database
   - Ensure parent directories exist
   
3. For each chunk in the file:
   - Check if the chunk exists locally by file_id and part_number
   - If the chunk exists and fingerprints match, keep the existing chunk
   - If the chunk doesn't exist or fingerprints don't match:
     - Download the chunk using the download endpoint
     - Store the chunk in the chunk directory
     - Update the chunk metadata in the database
   
4. Reconstruct the file from all chunks (both existing and newly downloaded)
5. Update the system_last_sync_time in the System table

### File Integrity Verification
- Use chunk fingerprints (SHA-256 hash) to verify data integrity
- Compare fingerprints between clients to ensure consistent file content

## Database Schema

### Client-Side SQLite Tables
1. **System Table**: Stores the last sync time
   ```sql
   CREATE TABLE system (
     id INTEGER PRIMARY KEY CHECK (id = 1),
     system_last_sync_time VARCHAR
   );
   ```

2. **Files Metadata Table**: Stores file metadata
   ```sql
   CREATE TABLE files_metadata (
     file_id VARCHAR PRIMARY KEY,
     file_type VARCHAR NOT NULL,
     file_path VARCHAR NOT NULL UNIQUE,
     file_name VARCHAR NOT NULL,
     file_hash VARCHAR,
     folder_id VARCHAR NOT NULL,
     FOREIGN KEY(folder_id) REFERENCES folders(folder_id)
   );
   ```

3. **Chunks Table**: Stores chunk metadata
   ```sql
   CREATE TABLE chunks (
     chunk_id VARCHAR NOT NULL,
     file_id VARCHAR NOT NULL,
     part_number INTEGER,
     created_at DATETIME,
     last_synced DATETIME,
     fingerprint VARCHAR NOT NULL,
     PRIMARY KEY(chunk_id, file_id),
     FOREIGN KEY(file_id) REFERENCES files_metadata(file_id)
   );
   ```

## Testing
1. Create E2E tests that verify file synchronization between clients
2. Test file creation on one client and verify it appears on another client
3. Verify file content matches between clients using both:
   - Chunk fingerprint comparison
   - Direct file checksum comparison

## Implementation Notes
1. Use file paths as the primary identifier for files, with file_id as a fallback
2. Use chunk fingerprints to identify changed chunks, not just timestamps
3. The sync process is a polling mechanism that happens every two minutes
4. Only download chunks that have changed, not entire files
5. Ensure proper error handling for network issues and file conflicts
6. Chunk fingerprints are critical for data integrity verification
