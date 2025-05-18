#!/bin/bash
#===================================================================================
# Start Multi-Client Containers
#===================================================================================
# Description: This script starts multiple Dropbox client containers using the
# generated docker-compose.multi.yml file. It first ensures that the AWS services
# and backend services are running, then starts the client containers.
#
# Usage: ./start_multi_client_containers.sh [num_clients]
#   num_clients: Number of client containers to start (default: 2)
#===================================================================================

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get the number of clients from the command line argument, default to 2
NUM_CLIENTS=${1:-2}

# Validate input
if ! [[ "$NUM_CLIENTS" =~ ^[0-9]+$ ]] || [ "$NUM_CLIENTS" -lt 1 ]; then
    echo -e "${RED}Error: Number of clients must be a positive integer.${NC}"
    exit 1
fi

# Define paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/deployment/client/docker-compose.multi.yml"

# Function to check if a container is running
is_container_running() {
    local container_name=$1
    if docker ps | grep -q "$container_name"; then
        return 0  # Container is running
    else
        return 1  # Container is not running
    fi
}

# Function to wait for a container to be ready
wait_for_container() {
    local container_name=$1
    local timeout=$2
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))

    echo -e "${YELLOW}Waiting for $container_name to be ready...${NC}"

    while ! is_container_running "$container_name"; do
        local current_time=$(date +%s)
        if [ $current_time -gt $end_time ]; then
            echo -e "${RED}Timeout waiting for $container_name to be ready.${NC}"
            return 1
        fi
        sleep 1
    done

    echo -e "${GREEN}$container_name is ready.${NC}"
    return 0
}

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Starting Multi-Client Environment${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "Number of clients: ${YELLOW}$NUM_CLIENTS${NC}"
echo -e "\n"

# Step 1: Generate the docker-compose.yml file
echo -e "${YELLOW}Generating docker-compose configuration...${NC}"
$SCRIPT_DIR/generate_multi_client_compose.sh $NUM_CLIENTS

# Step 1.5: Ensure the Docker network exists
echo -e "${YELLOW}Ensuring Docker network exists...${NC}"
if ! docker network ls | grep -q "dropbox-network"; then
    echo -e "${YELLOW}Creating dropbox-network...${NC}"
    docker network create dropbox-network
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Network created successfully.${NC}"
    else
        echo -e "${RED}Failed to create network. Please check docker logs.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Network dropbox-network already exists.${NC}"
fi

# Step 2: Check if AWS services are running
echo -e "${YELLOW}Checking if AWS services are running...${NC}"
if is_container_running "aws-s3" && is_container_running "aws-dynamodb"; then
    echo -e "${GREEN}AWS services are already running.${NC}"
else
    echo -e "${YELLOW}Starting AWS services...${NC}"
    cd $PROJECT_ROOT/deployment/aws
    docker compose up -d

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}AWS services started successfully.${NC}"
    else
        echo -e "${RED}Failed to start AWS services. Please check docker logs.${NC}"
        exit 1
    fi

    # Wait for AWS services to be ready
    wait_for_container "aws-s3" 60
    wait_for_container "aws-dynamodb" 60

    # Wait for initialization
    echo -e "${YELLOW}Waiting for AWS services to initialize (10 seconds)...${NC}"
    sleep 10
fi

# Step 3: Check if backend services are running
echo -e "${YELLOW}Checking if backend services are running...${NC}"
if is_container_running "files-service"; then
    echo -e "${GREEN}Backend services are already running.${NC}"
else
    echo -e "${YELLOW}Starting backend services...${NC}"
    cd $PROJECT_ROOT/deployment/backend
    docker compose up -d

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Backend services started successfully.${NC}"
    else
        echo -e "${RED}Failed to start backend services. Please check docker logs.${NC}"
        exit 1
    fi

    # Wait for backend services to be ready
    wait_for_container "files-service" 60

    # Wait for initialization
    echo -e "${YELLOW}Waiting for backend services to initialize (5 seconds)...${NC}"
    sleep 5
fi

# Step 4: Check for existing client containers and stop them if needed
echo -e "${YELLOW}Checking for existing client containers...${NC}"
for ((i=1; i<=$NUM_CLIENTS; i++)); do
    if is_container_running "dropbox-client-$i"; then
        echo -e "${YELLOW}Container dropbox-client-$i is already running. Stopping it...${NC}"
        docker stop dropbox-client-$i
        docker rm dropbox-client-$i
    fi
done

# Step 5: Start client containers
echo -e "${YELLOW}Starting client containers...${NC}"
cd $PROJECT_ROOT/deployment/client
docker compose -f docker-compose.multi.yml up -d

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Client containers started successfully.${NC}"
else
    echo -e "${RED}Failed to start client containers. Please check docker logs.${NC}"
    exit 1
fi

# Wait for client containers to be ready
for ((i=1; i<=$NUM_CLIENTS; i++)); do
    wait_for_container "dropbox-client-$i" 60
done

echo -e "\n${GREEN}Multi-client environment is now running!${NC}"
echo -e "${CYAN}Client API endpoints:${NC}"
for ((i=1; i<=$NUM_CLIENTS; i++)); do
    echo -e "  - Client $i: ${GREEN}http://localhost:910$i${NC}"
done

exit 0
