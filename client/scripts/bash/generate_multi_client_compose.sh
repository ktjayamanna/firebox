#!/bin/bash
#===================================================================================
# Generate Multi-Client Docker Compose Configuration
#===================================================================================
# Description: This script generates a docker-compose.yml file for multiple Firebox
# client containers. It takes the number of clients as an argument and creates a
# configuration with that many client containers, each with its own volumes.
#
# Usage: ./generate_multi_client_compose.sh [num_clients]
#   num_clients: Number of client containers to generate (default: 2)
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
OUTPUT_FILE="$PROJECT_ROOT/deployment/client/docker-compose.multi.yml"

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Generating Multi-Client Docker Compose Configuration${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "Number of clients: ${YELLOW}$NUM_CLIENTS${NC}"
echo -e "Output file: ${YELLOW}$OUTPUT_FILE${NC}"
echo -e "\n"

# Generate the docker-compose.yml file
cat > "$OUTPUT_FILE" << EOF
version: '3'

services:
EOF

# Generate client services
for ((i=1; i<=$NUM_CLIENTS; i++)); do
    cat >> "$OUTPUT_FILE" << EOF
  firebox-client-$i:
    build:
      context: ../../
      dockerfile: deployment/client/Dockerfile
    container_name: firebox-client-$i
    ports:
      - "910$i:8000"
    volumes:
      - ../../client/server:/app/server
      - ../../client/db:/app/db
      - ../../client/scripts:/app/scripts
      - ../../client/requirements.txt:/app/requirements.txt
      - ../../client/config.py:/app/config.py
      - firebox-data-$i:/app/my_firebox
      - db-data-$i:/app/data
      - chunk-data-$i:/app/tmp/chunk
    environment:
      - PYTHONPATH=/app
      - APP_DIR=/app
      - SYNC_DIR=/app/my_firebox
      - CHUNK_DIR=/app/tmp/chunk
      - DATABASE_URL=sqlite:///./data/firebox.db
      - DB_FILE_PATH=/app/data/firebox.db
      - DB_POOL_SIZE=20
      - DB_MAX_OVERFLOW=10
      - DB_POOL_TIMEOUT=30
      - DB_POOL_RECYCLE=3600
      - CHUNK_SIZE=5242880
      - API_HOST=0.0.0.0
      - API_PORT=8000
      - CLIENT_ID=client-$i
      # Files Service API settings
      - FILES_SERVICE_URL=http://files-service:8001
      - REQUEST_TIMEOUT=30
      - MAX_RETRIES=3
    networks:
      - firebox-network
    restart: unless-stopped

EOF
done

# Generate volumes
cat >> "$OUTPUT_FILE" << EOF
volumes:
EOF

for ((i=1; i<=$NUM_CLIENTS; i++)); do
    cat >> "$OUTPUT_FILE" << EOF
  firebox-data-$i:
    driver: local
  db-data-$i:
    driver: local
  chunk-data-$i:
    driver: local
EOF
done

# Add network configuration
cat >> "$OUTPUT_FILE" << EOF

networks:
  firebox-network:
    external: true
EOF

echo -e "${GREEN}Docker Compose configuration generated successfully!${NC}"
echo -e "You can start the multi-client environment with:"
echo -e "${CYAN}docker compose -f $OUTPUT_FILE up -d${NC}"

# Make the script executable
chmod +x "$OUTPUT_FILE"
