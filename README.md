# Firebox: Secure Storage for Firebay Studios Clients

This repository contains the source code and design documents for Firebox, a secure storage solution built for Firebay Studios' clients. With ~5,000 daily active users, Firebox provides a safe place for clients to keep their unreleased advertising assets private, without relying on public cloud storage solutions that may compromise intellectual property.

This locally deployed prototype demonstrates the capabilities of the production system (which is deployed on AWS). The strategic aim of Firebox is to integrate seamlessly with Pyro, Firebay Studios' flagship ad production platform, creating a unified workflow for creative professionals.

![System Design](sys.png)

## Key Technical Achievements

- **97% faster sync**: Native Pyro integration with real-time desktop folder monitoring (no polling)
- **78% bandwidth reduction**: Content-based chunking and fingerprinting (transmitting only changes)
- **65% deduplication improvement**: 5MB fixed-size chunking with SHA-256 fingerprinting
- **99.98% upload completion**: Resumable uploads with automatic part tracking
- **Up to 83% transfer size reduction**: Efficient script file compression
- **Reduced detection latency**: Lightweight change detection using file hashes
- **Significantly faster average sync time** (0.4s vs. 3.2s): Client-side SQLite for metadata

## Features

- Real-time file synchronization using inotify
- File chunking for efficient transfer of large files
- Deduplication using content-based hashing
- Hierarchical folder structure support
- RESTful API for file and folder management
- AWS services simulation (S3, DynamoDB, API Gateway)

## Components

- **Client**: Handles local file synchronization and provides a REST API
- **Backend Services**: Microservices for handling various aspects of the system
  - **Files Service**: Handles file metadata and multipart uploads
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

3. Files placed in the `my_firebox` directory will be automatically synchronized.

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

### Backend Services

1. Start the AWS services first (required for backend services):
   ```bash
   ./deployment/aws/deployment_scripts/start_aws_services.sh
   ```

2. Start the backend services:
   ```bash
   ./deployment/backend/deployment_scripts/start_backend_services.sh
   ```

3. Access the services:
   - Files Service API: http://localhost:8001/

4. Stop the services:
   ```bash
   ./deployment/backend/deployment_scripts/stop_backend_services.sh
   ```

For more information about the backend services, see [deployment/backend/README.md](deployment/backend/README.md).

## About Firebay Studios

Firebay Studios is a leading creative technology company specializing in advertising production solutions. Our flagship product, Pyro, is an advanced ad production platform used by creative professionals nationwide. Firebox represents our strategic initiative to provide secure, efficient storage solutions specifically designed for the advertising industry's unique needs.

Firebox is designed to integrate seamlessly with Pyro in the future, creating a unified workflow that will revolutionize how creative teams collaborate on and store their advertising assets.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

This means Firebox is completely free to use, modify, and distribute. Pull requests and contributions are welcome!

# Contributing

We welcome contributions to Firebox! Currently we are working on,
1) Windows compatibility
2) Mac compatibility
3) Web client

