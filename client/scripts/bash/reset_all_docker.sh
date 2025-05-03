#!/bin/bash
# reset_all_docker.sh
# Script to completely reset Docker by removing all containers, images, volumes, networks, etc.

# Set text colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${YELLOW}Docker Complete Reset Script${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${RED}WARNING: This will remove ALL Docker resources:${NC}"
echo -e "  - All running and stopped containers"
echo -e "  - All images"
echo -e "  - All volumes"
echo -e "  - All networks (except default ones)"
echo -e "  - All build cache"
echo -e "${BLUE}=========================================${NC}"

# Ask for confirmation
read -p "Are you sure you want to proceed? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 1
fi

echo -e "\n${BLUE}Starting Docker reset...${NC}"

# Stop all running containers
echo -e "\n${YELLOW}Step 1: Stopping all running containers...${NC}"
docker_running=$(docker ps -q)
if [ -z "$docker_running" ]; then
    echo -e "${GREEN}No running containers found.${NC}"
else
    docker stop $(docker ps -q)
    echo -e "${GREEN}All containers stopped.${NC}"
fi

# Remove all containers
echo -e "\n${YELLOW}Step 2: Removing all containers...${NC}"
docker_containers=$(docker ps -a -q)
if [ -z "$docker_containers" ]; then
    echo -e "${GREEN}No containers found.${NC}"
else
    docker rm -f $(docker ps -a -q)
    echo -e "${GREEN}All containers removed.${NC}"
fi

# Remove all volumes
echo -e "\n${YELLOW}Step 3: Removing all volumes...${NC}"
docker_volumes=$(docker volume ls -q)
if [ -z "$docker_volumes" ]; then
    echo -e "${GREEN}No volumes found.${NC}"
else
    docker volume rm $(docker volume ls -q)
    echo -e "${GREEN}All volumes removed.${NC}"
fi

# Remove all networks (except default ones)
echo -e "\n${YELLOW}Step 4: Removing all custom networks...${NC}"
docker_networks=$(docker network ls --filter "type=custom" -q)
if [ -z "$docker_networks" ]; then
    echo -e "${GREEN}No custom networks found.${NC}"
else
    docker network rm $(docker network ls --filter "type=custom" -q)
    echo -e "${GREEN}All custom networks removed.${NC}"
fi

# Remove all images
echo -e "\n${YELLOW}Step 5: Removing all images...${NC}"
docker_images=$(docker images -q)
if [ -z "$docker_images" ]; then
    echo -e "${GREEN}No images found.${NC}"
else
    docker rmi -f $(docker images -q)
    echo -e "${GREEN}All images removed.${NC}"
fi

# Prune system
echo -e "\n${YELLOW}Step 6: Pruning the system...${NC}"
docker system prune -a -f --volumes
echo -e "${GREEN}System pruned.${NC}"

# Verify everything is clean
echo -e "\n${YELLOW}Verifying clean state:${NC}"
echo -e "${BLUE}Containers:${NC}"
docker ps -a
echo -e "\n${BLUE}Images:${NC}"
docker images
echo -e "\n${BLUE}Volumes:${NC}"
docker volume ls
echo -e "\n${BLUE}Networks:${NC}"
docker network ls

echo -e "\n${GREEN}Docker reset complete!${NC}"
echo -e "${BLUE}=========================================${NC}"
