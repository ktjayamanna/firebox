# Firebox Backend Services

This directory contains Docker configurations for the backend microservices of the Firebox system.

## Services Included

1. **Files Service** - Handles file metadata and multipart uploads
   - External Port: 8001, Internal Port: 8001
   - Endpoints:
     - `POST /files`: Receive file metadata and return presigned URLs for multipart upload
     - `POST /files/confirm`: Confirm successful multipart upload and update chunk status

## Getting Started

### Prerequisites

Before starting the backend services, make sure the AWS services are running:

```bash
./deployment/aws/deployment_scripts/start_aws_services.sh
```

### Starting the Services

```bash
# Using the provided script
./deployment/backend/deployment_scripts/start_backend_services.sh

# Or manually
cd deployment/backend
docker compose up -d
```

### Accessing the Services

- **Files Service API**: http://localhost:8001/

### Checking Service Status

```bash
docker ps | grep files-service
```

### Stopping the Services

```bash
# Using the provided script
./deployment/backend/deployment_scripts/stop_backend_services.sh

# Or manually
cd deployment/backend
docker compose down
```

To remove all data volumes:

```bash
# Using the provided script
./deployment/backend/deployment_scripts/stop_backend_services.sh -v

# Or manually
cd deployment/backend
docker compose down -v
```

## Configuration

The services are configured using environment variables in the docker-compose.yml file. You can modify these variables to change the behavior of the services.

### Files Service

- `AWS_ACCESS_KEY_ID`: AWS access key ID for S3 access
- `AWS_SECRET_ACCESS_KEY`: AWS secret access key for S3 access
- `AWS_REGION`: AWS region for S3 and DynamoDB
- `S3_ENDPOINT`: S3 endpoint URL
- `S3_BUCKET_NAME`: S3 bucket name for storing file chunks
- `S3_USE_SSL`: Whether to use SSL for S3 connections
- `DYNAMODB_HOST`: DynamoDB endpoint URL
- `DYNAMODB_REGION`: DynamoDB region
- `API_HOST`: API host address
- `API_PORT`: API port
- `CHUNK_SIZE`: Size of file chunks in bytes
- `PRESIGNED_URL_EXPIRATION`: Expiration time for presigned URLs in seconds
