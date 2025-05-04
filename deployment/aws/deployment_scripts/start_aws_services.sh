#!/bin/bash
# Script to start the AWS services containers

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Starting AWS Services Containers${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    exit 1
fi

# Check if docker-compose is installed
if ! command -v docker compose &> /dev/null; then
    echo -e "${RED}Error: Docker Compose is not installed or not in PATH${NC}"
    exit 1
fi

# Navigate to the aws directory
cd "$(dirname "$0")/.." || {
    echo -e "${RED}Error: Could not navigate to the aws directory${NC}"
    exit 1
}

# Start the containers
echo -e "${YELLOW}Starting containers...${NC}"
docker compose up -d

# Check if containers are running
if [ $? -eq 0 ]; then
    echo -e "${GREEN}AWS services started successfully!${NC}"
    echo -e "${YELLOW}Services available at:${NC}"
    echo -e "  - API Gateway: ${GREEN}http://localhost:8080/${NC}"
    echo -e "  - MinIO Console: ${GREEN}http://localhost:8080/minio-console/${NC}"
    echo -e "    Username: minioadmin"
    echo -e "    Password: minioadmin"
    echo -e "  - S3 API: ${GREEN}http://localhost:8080/s3/${NC}"
    echo -e "  - DynamoDB API: ${GREEN}http://localhost:8080/dynamodb/${NC}"
else
    echo -e "${RED}Failed to start AWS services. Check docker logs for details.${NC}"
    exit 1
fi

echo -e "${BLUE}=========================================${NC}"
