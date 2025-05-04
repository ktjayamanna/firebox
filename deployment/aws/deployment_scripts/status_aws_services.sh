#!/bin/bash
# Script to check the status of AWS services containers

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${CYAN}AWS Services Status${NC}"
echo -e "${BLUE}=========================================${NC}"

# Navigate to the aws directory
cd "$(dirname "$0")/.." || {
    echo -e "${RED}Error: Could not navigate to the aws directory${NC}"
    exit 1
}

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    exit 1
fi

# Get container status
echo -e "${YELLOW}Checking container status...${NC}"
CONTAINERS=("aws-s3" "aws-dynamodb" "aws-api-gateway" "minio-setup" "dynamodb-setup")

echo -e "\n${CYAN}Container Status:${NC}"
printf "%-20s %-15s %-15s %-30s\n" "CONTAINER" "STATUS" "PORTS" "CREATED"
echo "--------------------------------------------------------------------------------"

for container in "${CONTAINERS[@]}"; do
    # Get container info
    CONTAINER_INFO=$(docker ps -a --filter "name=$container" --format "{{.Status}}|{{.Ports}}|{{.CreatedAt}}")

    if [ -z "$CONTAINER_INFO" ]; then
        printf "%-20s ${RED}%-15s${NC} %-15s %-30s\n" "$container" "NOT FOUND" "-" "-"
    else
        # Parse container info
        IFS='|' read -r STATUS PORTS CREATED <<< "$CONTAINER_INFO"

        # Check if container is running
        if [[ $STATUS == "Up"* ]]; then
            printf "%-20s ${GREEN}%-15s${NC} %-15s %-30s\n" "$container" "Running" "${PORTS:0:15}" "${CREATED:0:30}"
        else
            printf "%-20s ${RED}%-15s${NC} %-15s %-30s\n" "$container" "Stopped" "${PORTS:0:15}" "${CREATED:0:30}"
        fi
    fi
done

# Check service accessibility
echo -e "\n${CYAN}Service Accessibility:${NC}"

# Check Nginx (API Gateway)
echo -ne "API Gateway (Nginx): "
if curl -s --head --fail http://localhost:8080/ > /dev/null; then
    echo -e "${GREEN}Accessible${NC}"
else
    echo -e "${RED}Not accessible${NC}"
fi

# Check MinIO Console
echo -ne "MinIO Console: "
if curl -s --head --fail http://localhost:8080/minio-console/ > /dev/null; then
    echo -e "${GREEN}Accessible${NC}"
else
    echo -e "${RED}Not accessible${NC}"
fi

# Check S3 API
echo -ne "S3 API (MinIO): "
if curl -s --head --fail http://localhost:8080/s3/ > /dev/null; then
    echo -e "${GREEN}Accessible${NC}"
else
    echo -e "${RED}Not accessible${NC}"
fi

# Check DynamoDB API
echo -ne "DynamoDB API: "
if curl -s --head --fail http://localhost:8080/dynamodb/ > /dev/null; then
    echo -e "${GREEN}Accessible${NC}"
else
    echo -e "${RED}Not accessible${NC}"
fi

echo -e "\n${YELLOW}To start services:${NC} ./deployment_scripts/start_aws_services.sh"
echo -e "${YELLOW}To stop services:${NC} ./deployment_scripts/stop_aws_services.sh"
echo -e "${YELLOW}To stop and remove volumes:${NC} ./deployment_scripts/stop_aws_services.sh -v"

echo -e "${BLUE}=========================================${NC}"
