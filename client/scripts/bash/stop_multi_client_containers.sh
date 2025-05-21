#!/bin/bash
#===================================================================================
# Stop Multi-Client Containers
#===================================================================================
# Description: This script stops the multi-client Firebox containers that were
# started with the start_multi_client_containers.sh script.
#
# Usage: ./stop_multi_client_containers.sh [--clean]
#   --clean: Optional flag to remove all volumes and data
#===================================================================================

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse command line arguments
DO_CLEAN=false
for arg in "$@"; do
    case $arg in
        --clean)
            DO_CLEAN=true
            shift
            ;;
    esac
done

# Define paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/deployment/client/docker-compose.multi.yml"

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Stopping Multi-Client Environment${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if the compose file exists
if [ ! -f "$COMPOSE_FILE" ]; then
    echo -e "${RED}Error: Docker Compose file not found at $COMPOSE_FILE${NC}"
    echo -e "${YELLOW}Run start_multi_client_containers.sh first to generate the file.${NC}"
    exit 1
fi

# Stop the containers
echo -e "${YELLOW}Stopping client containers...${NC}"
cd $PROJECT_ROOT/deployment/client

if [ "$DO_CLEAN" = true ]; then
    echo -e "${YELLOW}Removing containers and volumes...${NC}"
    docker compose -f docker-compose.multi.yml down -v
else
    echo -e "${YELLOW}Stopping containers (keeping volumes)...${NC}"
    docker compose -f docker-compose.multi.yml down
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Client containers stopped successfully.${NC}"
else
    echo -e "${RED}Failed to stop client containers. Please check docker logs.${NC}"
    exit 1
fi

echo -e "\n${GREEN}Multi-client environment has been stopped.${NC}"
if [ "$DO_CLEAN" = true ]; then
    echo -e "${YELLOW}All volumes and data have been removed.${NC}"
else
    echo -e "${YELLOW}Volumes and data have been preserved.${NC}"
    echo -e "${YELLOW}Use --clean flag to remove all volumes and data.${NC}"
fi

exit 0
