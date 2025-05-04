#!/bin/bash
# Script to stop the AWS services containers

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${YELLOW}Stopping AWS Services Containers${NC}"
echo -e "${BLUE}=========================================${NC}"

# Navigate to the aws directory
cd "$(dirname "$0")/.." || {
    echo -e "${RED}Error: Could not navigate to the aws directory${NC}"
    exit 1
}

# Check if we should remove volumes
if [ "$1" == "-v" ] || [ "$1" == "--volumes" ]; then
    echo -e "${YELLOW}Stopping containers and removing volumes...${NC}"
    docker compose down -v
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}AWS services stopped and volumes removed successfully!${NC}"
    else
        echo -e "${RED}Failed to stop AWS services. Check docker logs for details.${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}Stopping containers...${NC}"
    docker compose down
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}AWS services stopped successfully!${NC}"
        echo -e "${YELLOW}Note: Data volumes were preserved. To remove volumes, use:${NC}"
        echo -e "  ./deployment_scripts/stop_aws_services.sh -v"
    else
        echo -e "${RED}Failed to stop AWS services. Check docker logs for details.${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}=========================================${NC}"
