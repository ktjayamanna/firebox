-- Display files_metadata and chunks tables in a nicely formatted way
.timeout 10000
.echo on
.headers on
.mode box

-- View all records in files_metadata table with nice formatting (limited to 10)
.print '\n=== FILES METADATA TABLE (LIMITED TO 10) ===\n'
SELECT
    file_id AS "File ID",
    file_path AS "File Path",
    parent_path AS "Parent Path",
    file_name AS "File Name",
    file_type AS "File Type",
    CASE
        WHEN file_hash IS NULL THEN 'N/A (directory)'
        ELSE substr(file_hash, 1, 10) || '...'
    END AS "File Hash"
FROM
    files_metadata
LIMIT 10;

-- View directory structure
.print '\n=== DIRECTORY STRUCTURE ===\n'
WITH RECURSIVE dirs AS (
    -- Root directories (those with no parent or parent is outside sync dir)
    SELECT
        file_id,
        file_path,
        parent_path,
        file_name,
        0 AS level,
        file_name AS path_display
    FROM
        files_metadata
    WHERE
        file_type = 'directory' AND
        (parent_path IS NULL OR parent_path = '/app')

    UNION ALL

    -- Child directories
    SELECT
        f.file_id,
        f.file_path,
        f.parent_path,
        f.file_name,
        d.level + 1,
        d.path_display || '/' || f.file_name AS path_display
    FROM
        files_metadata f
    JOIN
        dirs d ON f.parent_path = d.file_path
    WHERE
        f.file_type = 'directory'
)
SELECT
    printf('%s%s', printf('%.' || (level * 2) || 'c', ' '), file_name) AS "Directory Structure",
    file_path AS "Full Path"
FROM
    dirs
ORDER BY
    path_display;

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
