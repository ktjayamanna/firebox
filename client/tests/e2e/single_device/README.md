# Firebox Client Single Device E2E Tests

This directory contains end-to-end (E2E) tests for the Firebox client that can be run on a single device. These tests verify the core functionality of the client without requiring multiple devices or clients to be synchronized.

## Overview

The tests in this directory focus on the following aspects of the Firebox client:

1. **Core File Synchronization**: Basic file upload and synchronization
2. **File Chunking**: Splitting large files into chunks
3. **File Modifications**: Handling file content changes
4. **File Deletion**: Removing files from the sync directory
5. **Move and Rename Operations**: Moving and renaming files and folders
6. **Folder Management**: Creating and managing folder hierarchies
7. **Content Deduplication**: Avoiding duplicate storage of identical content
8. **Large File Support**: Handling files larger than the chunk size
9. **File Modification Behavior**: Detailed testing of how file modifications are handled

## Running the Tests

To run all the tests in this directory:

```bash
./run_single_device_tests.sh
```

This will execute all the tests in sequence and provide a summary of the results.

## Test Descriptions

### 1. Core File Synchronization (`test_core_file_sync.sh`)

Tests the basic functionality of uploading files to the sync directory and verifying they are properly processed and stored in the database.

- Creates files of different sizes (small, medium, large)
- Copies them to the sync directory
- Verifies they exist in the container
- Checks if they are properly recorded in the database
- Verifies API access to the files

### 2. File Chunking (`test_file_chunking.sh`)

Tests the system's ability to split files into chunks for efficient storage and transfer.

- Creates a file larger than the chunk size
- Verifies it's properly split into chunks
- Checks that chunk metadata is correctly stored in the database
- Verifies chunk files are created on disk

### 3. File Modifications (`test_file_modifications.sh`)

Tests how the system handles file content changes.

- Creates a test file and verifies it's processed
- Modifies the file content
- Verifies the file hash is updated in the database
- Checks that chunks are updated appropriately

**Important Note**: When a file is modified, the system creates a new file record with a new ID rather than updating the existing record. This is an intentional design choice that allows for efficient handling of file versions.

### 4. File Deletion (`test_file_deletion.sh`)

Tests the system's ability to handle file deletions.

- Creates test files and verifies they're processed
- Deletes one of the files
- Verifies the file is removed from the database
- Checks that associated chunks are also removed

### 5. Move and Rename Operations (`test_move_rename.sh`)

Tests the system's ability to handle file and folder moves and renames.

- Creates test folders and files
- Moves a file from one folder to another
- Renames a file
- Renames a folder
- Verifies the changes are reflected in the database

### 6. Folder Management (`test_folder_management.sh`)

Tests the system's ability to handle folder hierarchies.

- Creates a deeply nested folder structure
- Creates files at different levels of the hierarchy
- Verifies folders and files are properly associated in the database

### 7. Content Deduplication (`test_content_deduplication.sh`)

Tests the system's ability to avoid storing duplicate content.

- Creates a file with specific content
- Creates a duplicate file with the same content but a different name
- Verifies both files have the same hash in the database
- Checks that chunk fingerprints match between the files

### 8. Large File Support (`test_large_file_support.sh`)

Tests the system's ability to handle files larger than the chunk size.

- Creates a large file (20MB)
- Verifies it's properly split into chunks
- Tests downloading a subset of chunks
- Verifies the downloaded chunks

### 9. File Modification Behavior (`test_file_modification_behavior.sh`)

Tests in detail how the system handles file modifications.

- Creates a test file and verifies it's processed
- Modifies the file content
- Checks for chunks at different time intervals
- Reveals the system's behavior with file modifications

## Key Insights

### File Modification Behavior

When a file is modified, the system:

1. **Creates a new file record** with a new file ID
2. **Processes chunks immediately** (not asynchronously)
3. **Reuses chunks that haven't changed** (content-based deduplication)
4. **Only creates new chunks for the parts of the file that have changed**

This approach is efficient and robust, as it:
- Preserves the history of file versions
- Minimizes storage requirements through chunk-level deduplication
- Processes changes quickly without delays
- Handles partial file modifications efficiently

### Move and Rename Operations

The system handles move and rename operations by:

1. **Updating existing records** instead of creating new ones
2. **Maintaining file and folder relationships** in the database
3. **Recursively updating paths** for nested folders and their contents

## Test Logs

Test logs are stored in the `client/tests/logs/` directory with timestamps in the filename.
