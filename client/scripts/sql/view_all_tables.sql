-- Display folders, files_metadata and chunks tables in a nicely formatted way
.timeout 10000
.echo on
.headers on
.mode box

-- View all records in folders table with nice formatting (limited to 10)
.print '\n=== FOLDERS TABLE (LIMITED TO 10) ===\n'
SELECT
    folder_id AS "Folder ID",
    folder_path AS "Folder Path",
    folder_name AS "Folder Name",
    parent_folder_id AS "Parent Folder ID"
FROM
    folders
LIMIT 10;

-- View all records in files_metadata table with nice formatting (limited to 10)
.print '\n=== FILES METADATA TABLE (LIMITED TO 10) ===\n'
SELECT
    file_id AS "File ID",
    file_path AS "File Path",
    file_name AS "File Name",
    file_type AS "File Type",
    folder_id AS "Folder ID",
    substr(file_hash, 1, 10) || '...' AS "File Hash"
FROM
    files_metadata
LIMIT 10;

-- View directory structure
.print '\n=== DIRECTORY STRUCTURE ===\n'
WITH RECURSIVE dirs AS (
    -- Root folders (those with null parent)
    SELECT
        folder_id,
        folder_path,
        folder_name,
        parent_folder_id,
        0 AS level,
        folder_name AS path_display
    FROM
        folders
    WHERE
        parent_folder_id IS NULL

    UNION ALL

    -- Child folders
    SELECT
        f.folder_id,
        f.folder_path,
        f.folder_name,
        f.parent_folder_id,
        d.level + 1,
        d.path_display || '/' || f.folder_name AS path_display
    FROM
        folders f
    JOIN
        dirs d ON f.parent_folder_id = d.folder_id
)
SELECT
    printf('%s%s', printf('%.' || (level * 2) || 'c', ' '), folder_name) AS "Directory Structure",
    folder_path AS "Full Path"
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

-- View system table (singleton table)
.print '\n=== SYSTEM TABLE ===\n'
SELECT
    id AS "ID",
    system_last_sync_time AS "Last Sync Time"
FROM
    system
UNION ALL
SELECT
    0 AS "ID",
    'No system record found' AS "Last Sync Time"
WHERE
    NOT EXISTS (SELECT 1 FROM system LIMIT 1);
