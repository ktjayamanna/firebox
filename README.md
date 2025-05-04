# Dropbox System Design

This repository contains the source code and design documents for a Dropbox-like file synchronization system. The system is designed to efficiently synchronize files across multiple devices with support for large files.

![System Design](sys.png)

## Features

- Real-time file synchronization using inotify
- File chunking for efficient transfer of large files
- Deduplication using content-based hashing
- Hierarchical folder structure support
- RESTful API for file and folder management
- AWS services simulation (S3, DynamoDB, API Gateway)

## Components

- **Client**: Handles local file synchronization and provides a REST API
- **Database**: SQLite database for storing file metadata and chunk information
- **Chunking System**: Splits files into chunks for efficient storage and transfer
- **AWS Services**: Simulated AWS services for development and testing
  - **MinIO**: S3-compatible object storage
  - **DynamoDB Local**: DynamoDB-compatible NoSQL database
  - **Nginx**: API Gateway for routing and rate limiting

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

### Client

1. Start the Docker container:
   ```bash
   ./client/scripts/bash/start_client_container.sh
   ```

2. Access the API at http://localhost:8000

3. Files placed in the `my_dropbox` directory will be automatically synchronized.

### AWS Services

1. Start the AWS services:
   ```bash
   ./deployment/aws/deployment_scripts/start_aws_services.sh
   ```

2. Access the services:
   - API Gateway: http://localhost:8080/
   - MinIO Console: http://localhost:8080/minio-console/ (login: minioadmin/minioadmin)
   - S3 API: http://localhost:8080/s3/
   - DynamoDB API: http://localhost:8080/dynamodb/

3. Stop the services:
   ```bash
   ./deployment/aws/deployment_scripts/stop_aws_services.sh
   ```

For more information about the AWS services, see [deployment/aws/README.md](deployment/aws/README.md).

## Acknowledgements

Many thanks to [Hello Interview](https://www.hellointerview.com/learn/system-design/problem-breakdowns/dropbox) for the original design.
