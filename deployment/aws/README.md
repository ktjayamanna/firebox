# AWS Services Simulation

This directory contains Docker configurations to simulate AWS services locally for development and testing purposes.

## Services Included

1. **MinIO** - S3-compatible object storage
   - API Port: 9000
   - Console Port: 9001
   - Accessible via Nginx at: http://localhost:8080/s3/ and http://localhost:8080/minio-console/

2. **DynamoDB Local** - DynamoDB-compatible NoSQL database
   - Port: 8002
   - Accessible via Nginx at: http://localhost:8080/dynamodb/

3. **Nginx** - Simulates API Gateway for routing and rate limiting
   - Port: 8080
   - Provides a unified interface to all services

## Getting Started

### Starting the Services

```bash
# Using the provided script
./deployment_scripts/start_aws_services.sh

# Or manually
cd deployment/aws
docker compose up -d
```

### Accessing the Services

- **API Gateway**: http://localhost:8080/
- **MinIO Console**: http://localhost:8080/minio-console/
  - Username: minioadmin
  - Password: minioadmin
- **S3 API**: http://localhost:8080/s3/
- **DynamoDB API**: http://localhost:8080/dynamodb/

### Checking Service Status

```bash
./deployment_scripts/status_aws_services.sh
```

### Stopping the Services

```bash
# Using the provided script
./deployment_scripts/stop_aws_services.sh

# Or manually
cd deployment/aws
docker compose down
```

To remove all data volumes:

```bash
# Using the provided script
./deployment_scripts/stop_aws_services.sh -v

# Or manually
cd deployment/aws
docker compose down -v
```

## Configuration

### MinIO (S3)

- The setup automatically creates a bucket named `dropbox-chunks` with public access policy.
- You can modify the bucket configuration in the `minio-setup` service in the docker-compose.yml file.

### DynamoDB

- The setup automatically creates the following tables:
  - `FilesMetaData`
  - `Chunks`
  - `Folders`
- Table schemas match the SQLite database schema used in the client.

### Nginx (API Gateway)

- Configured with rate limiting:
  - 10 requests per second with a burst of up to 20 requests for S3 endpoints
  - 10 requests per second with a burst of up to 5 requests for DynamoDB endpoints
- You can modify the rate limiting and routing in the Nginx configuration files.

## Using with the Client

To use these simulated AWS services with the client, you would need to modify the client code to:

1. Store chunks in S3 (MinIO) instead of the local filesystem
2. Store metadata in DynamoDB instead of SQLite
3. Route API requests through the Nginx API Gateway

This is not implemented in the current version of the client but could be added as a future enhancement.
