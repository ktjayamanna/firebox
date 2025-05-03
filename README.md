# Dropbox System Design

This repository contains the source code and design documents for a Dropbox-like file synchronization system. The system is designed to efficiently synchronize files across multiple devices with support for large files.

![System Design](sys.png)

## Features

- Real-time file synchronization using inotify
- File chunking for efficient transfer of large files
- Deduplication using content-based hashing
- Hierarchical folder structure support
- RESTful API for file and folder management

## Components

- **Client**: Handles local file synchronization and provides a REST API
- **Database**: SQLite database for storing file metadata and chunk information
- **Chunking System**: Splits files into chunks for efficient storage and transfer

## Testing

The system includes a comprehensive test suite to verify functionality:

```bash
# Run all smoke tests
./client/tests/smoke/run_all_tests.sh

# Run specific tests
./client/tests/smoke/test_file_sync.sh
./client/tests/smoke/test_file_modifications.sh
./client/tests/smoke/test_folder_operations.sh
./client/tests/smoke/test_api_endpoints.sh
```

For more information about the test suite, see [client/tests/README.md](client/tests/README.md).

## Getting Started

1. Start the Docker container:
   ```bash
   cd deployment/docker
   docker-compose up -d
   ```

2. Access the API at http://localhost:8000

3. Files placed in the `my_dropbox` directory will be automatically synchronized.

## Acknowledgements

Many thanks to [Hello Interview](https://www.hellointerview.com/learn/system-design/problem-breakdowns/dropbox) for the original design.
