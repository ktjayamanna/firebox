# Dropbox Client Test Suite

This directory contains tests for the Dropbox client application. The tests are organized into different categories to verify various aspects of the system's functionality.

## Test Categories

### Smoke Tests

Located in the `smoke` directory, these tests verify the basic functionality of the Dropbox client. They ensure that the core features are working as expected.

#### Available Smoke Tests

1. **File Synchronization Test** (`test_file_sync.sh`)
   - Tests basic file upload and synchronization
   - Verifies files are properly tracked in the database
   - Checks folder creation and tracking

2. **File Modifications Test** (`test_file_modifications.sh`)
   - Tests file content modification detection
   - Verifies hash changes are detected and recorded
   - Checks chunk recreation on file modification

3. **Folder Operations Test** (`test_folder_operations.sh`)
   - Tests nested folder structure creation
   - Verifies parent-child folder relationships
   - Checks file creation in nested folders

4. **API Endpoints Test** (`test_api_endpoints.sh`)
   - Tests all API endpoints for proper functionality
   - Verifies file and folder metadata retrieval
   - Checks system health endpoints

## Running the Tests

### Prerequisites

- Docker must be installed and running
- The Dropbox client container must be built (it will be started automatically by the test scripts if not running)

### Running All Tests

To run all smoke tests at once, use the following command from the project root:

```bash
./client/tests/smoke/run_all_tests.sh
```

This script will:
1. Start the Docker container if it's not already running
2. Clean up the sync directory to ensure a fresh test environment
3. Run each test script in sequence
4. Display the results of each test

### Running Individual Tests

You can also run individual test scripts directly:

```bash
# Run file sync test
./client/tests/smoke/test_file_sync.sh

# Run file modifications test
./client/tests/smoke/test_file_modifications.sh

# Run folder operations test
./client/tests/smoke/test_folder_operations.sh

# Run API endpoints test
./client/tests/smoke/test_api_endpoints.sh
```

## Test Data

The tests use mock data located in the `mock_data` directory. This includes:
- Small text files
- Medium-sized binary files
- Nested folder structures

## Troubleshooting

If tests are failing, check the following:

1. **Docker Container Status**
   ```bash
   docker ps | grep dropbox-client
   ```

2. **Container Logs**
   ```bash
   docker logs dropbox-client
   ```

3. **Database Content**
   ```bash
   docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT * FROM folders;"
   docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT * FROM files_metadata;"
   docker exec dropbox-client sqlite3 /app/data/dropbox.db "SELECT * FROM chunks;"
   ```

4. **Sync Directory Content**
   ```bash
   docker exec dropbox-client ls -la /app/my_dropbox
   ```
