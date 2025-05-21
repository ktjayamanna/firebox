# Firebox Multi-Device E2E Tests

This directory contains end-to-end tests for the Firebox client in a multi-device environment. These tests verify that multiple client devices can operate independently with the same backend services.

## Test Environment

The multi-device tests run against a Docker environment with:
- Multiple client containers (by default, 2 clients)
- Shared backend services (files-service)
- Shared AWS services (S3, DynamoDB)

Each client has its own:
- Sync directory
- SQLite database
- Chunk storage
- API endpoint

## Test Categories

The tests cover the same functionality as the single-device tests, but in a multi-device context:

1. **Core File Synchronization**: Basic file upload and synchronization on multiple devices
2. **File Chunking**: Splitting large files into chunks on multiple devices
3. **File Modifications**: Handling file content changes on multiple devices
4. **File Deletion**: Removing files from the sync directory on multiple devices
5. **Move and Rename Operations**: Moving and renaming files and folders on multiple devices
6. **Folder Management**: Creating and managing folder hierarchies on multiple devices
7. **Content Deduplication**: Avoiding duplicate storage of identical content across devices
8. **Large File Support**: Handling files larger than the chunk size on multiple devices
9. **File Modification Behavior**: Detailed testing of how file modifications are handled on multiple devices

## Running the Tests

To run all the tests in this directory:

```bash
./run_multi_device_tests.sh
```

This will:
1. Check if the multi-client containers are running, and start them if needed
2. Execute all the tests in sequence
3. Provide a summary of the results

## Client Identification

Each client is identified by a unique CLIENT_ID environment variable:
- Client 1: `client-1`
- Client 2: `client-2`

This ID is used to distinguish between clients in the logs and API responses.

## API Endpoints

Each client exposes its API on a different port:
- Client 1: http://localhost:9101
- Client 2: http://localhost:9102

## Starting and Stopping the Multi-Client Environment

To manually start the multi-client environment:

```bash
./client/scripts/bash/start_multi_client_containers.sh [num_clients]
```

To stop the multi-client environment:

```bash
./client/scripts/bash/stop_multi_client_containers.sh [--clean]
```

Use the `--clean` flag to remove all volumes and data.

## Test Implementation Notes

Each test follows a similar pattern:
1. Create test data
2. Copy the data to each client's sync directory
3. Verify the data is processed correctly on each client
4. Clean up

The tests verify that each client operates independently with the same backend services.
