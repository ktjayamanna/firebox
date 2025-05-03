-- Display files_metadata and chunks tables in a nicely formatted way
.echo on
.headers on
.mode box

-- View all records in files_metadata table with nice formatting (limited to 5)
.print '\n=== FILES METADATA TABLE (LIMITED TO 5) ===\n'
SELECT 
    file_id AS "File ID",
    folder_id AS "Folder ID",
    file_type AS "File Type"
FROM 
    files_metadata
LIMIT 5;

-- View all records in chunks table with nice formatting (limited to 5)
.print '\n=== CHUNKS TABLE (LIMITED TO 5) ===\n'
SELECT 
    chunk_id AS "Chunk ID",
    file_id AS "File ID",
    datetime(created_at) AS "Created At",
    datetime(last_synced) AS "Last Synced",
    fingerprint AS "Fingerprint"
FROM 
    chunks
UNION ALL
SELECT 
    'No chunks found' AS "Chunk ID",
    '' AS "File ID",
    '' AS "Created At",
    '' AS "Last Synced",
    '' AS "Fingerprint"
WHERE 
    NOT EXISTS (SELECT 1 FROM chunks LIMIT 1)
LIMIT 5;
