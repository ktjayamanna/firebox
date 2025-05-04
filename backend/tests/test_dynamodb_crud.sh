#!/bin/bash
# End-to-end test script for DynamoDB CRUD operations
# This script tests DynamoDB functionality using AWS CLI

set -e  # Exit immediately if a command exits with a non-zero status

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# DynamoDB configuration
ENDPOINT_URL="http://localhost:8002"
AWS_REGION="us-east-1"
AWS_ACCESS_KEY_ID="dummy"
AWS_SECRET_ACCESS_KEY="dummy"

# Table names
FILES_TABLE="FilesMetaData"
CHUNKS_TABLE="Chunks"
FOLDERS_TABLE="Folders"

# Print header
echo -e "${YELLOW}====================================${NC}"
echo -e "${YELLOW}  DynamoDB CRUD End-to-End Tests   ${NC}"
echo -e "${YELLOW}====================================${NC}"

# Check if required commands exist
echo -e "\n${YELLOW}Checking required dependencies...${NC}"
for cmd in docker aws jq; do
  if command -v $cmd >/dev/null 2>&1; then
    echo -e "✅ $cmd is installed"
  else
    echo -e "${RED}❌ $cmd is not installed. Please install it and try again.${NC}"
    exit 1
  fi
done

# Get the project root directory
PROJECT_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
echo -e "\n${YELLOW}Project root: ${PROJECT_ROOT}${NC}"

# Check if DynamoDB container is running
echo -e "\n${YELLOW}Checking if DynamoDB container is running...${NC}"
if docker ps | grep -q aws-dynamodb; then
  echo -e "✅ DynamoDB container is already running"
else
  echo -e "${YELLOW}⚠️ DynamoDB container is not running. Starting it now...${NC}"
  
  # Check if docker-compose.yml exists
  if [ -f "${PROJECT_ROOT}/deployment/aws/docker-compose.yml" ]; then
    # Start the container using docker-compose
    cd "${PROJECT_ROOT}/deployment/aws"
    docker-compose up -d
    
    if [ $? -ne 0 ]; then
      echo -e "${RED}❌ Failed to start DynamoDB container. Please check the docker-compose.yml file.${NC}"
      exit 1
    fi
    
    # Go back to the original directory
    cd - > /dev/null
    
    # Wait for the container to be ready
    echo -e "${YELLOW}Waiting for DynamoDB container to be ready...${NC}"
    sleep 5
    
    if docker ps | grep -q aws-dynamodb; then
      echo -e "✅ DynamoDB container is now running"
    else
      echo -e "${RED}❌ DynamoDB container failed to start. Please check the logs.${NC}"
      exit 1
    fi
  else
    echo -e "${RED}❌ docker-compose.yml not found at ${PROJECT_ROOT}/deployment/aws/docker-compose.yml${NC}"
    exit 1
  fi
fi

# Configure AWS CLI
export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$AWS_REGION

# List tables
echo -e "\n${BLUE}=== Listing DynamoDB Tables ===${NC}"
TABLES=$(aws dynamodb list-tables --endpoint-url $ENDPOINT_URL)
echo "$TABLES" | jq

# Check if required tables exist
echo -e "\n${YELLOW}Checking if required tables exist...${NC}"
TABLE_NAMES=$(echo "$TABLES" | jq -r '.TableNames[]')

for table in $FILES_TABLE $CHUNKS_TABLE $FOLDERS_TABLE; do
  if echo "$TABLE_NAMES" | grep -q "$table"; then
    echo -e "✅ Table $table exists"
  else
    echo -e "${YELLOW}⚠️ Table $table does not exist. Creating it now...${NC}"
    
    if [ "$table" = "$FOLDERS_TABLE" ]; then
      # Create Folders table
      aws dynamodb create-table \
        --endpoint-url $ENDPOINT_URL \
        --table-name $FOLDERS_TABLE \
        --attribute-definitions AttributeName=folder_id,AttributeType=S \
        --key-schema AttributeName=folder_id,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
      
      echo -e "✅ Created $FOLDERS_TABLE table"
    
    elif [ "$table" = "$FILES_TABLE" ]; then
      # Create FilesMetaData table
      aws dynamodb create-table \
        --endpoint-url $ENDPOINT_URL \
        --table-name $FILES_TABLE \
        --attribute-definitions AttributeName=file_id,AttributeType=S \
        --key-schema AttributeName=file_id,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
      
      echo -e "✅ Created $FILES_TABLE table"
    
    elif [ "$table" = "$CHUNKS_TABLE" ]; then
      # Create Chunks table
      aws dynamodb create-table \
        --endpoint-url $ENDPOINT_URL \
        --table-name $CHUNKS_TABLE \
        --attribute-definitions \
          AttributeName=chunk_id,AttributeType=S \
          AttributeName=file_id,AttributeType=S \
        --key-schema \
          AttributeName=chunk_id,KeyType=HASH \
          AttributeName=file_id,KeyType=RANGE \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
      
      echo -e "✅ Created $CHUNKS_TABLE table"
    fi
    
    # Wait for table to be created
    echo -e "${YELLOW}Waiting for table to be active...${NC}"
    sleep 5
  fi
done

# Generate a UUID
generate_uuid() {
  cat /proc/sys/kernel/random/uuid
}

# Test Folders CRUD operations
echo -e "\n${BLUE}=== Testing Folders CRUD Operations ===${NC}"

# Generate test data
FOLDER_ID="test-folder-$(generate_uuid)"
FOLDER_PATH="/test/folder/$(generate_uuid)"
FOLDER_NAME="test-folder-$(generate_uuid)"

# CREATE operation
echo -e "\n${YELLOW}--- CREATE Operation ---${NC}"
aws dynamodb put-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FOLDERS_TABLE \
  --item "{\"folder_id\":{\"S\":\"$FOLDER_ID\"},\"folder_path\":{\"S\":\"$FOLDER_PATH\"},\"folder_name\":{\"S\":\"$FOLDER_NAME\"}}"

echo -e "✅ Successfully created folder: $FOLDER_ID"

# READ operation
echo -e "\n${YELLOW}--- READ Operation ---${NC}"
FOLDER_DATA=$(aws dynamodb get-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FOLDERS_TABLE \
  --key "{\"folder_id\":{\"S\":\"$FOLDER_ID\"}}")

echo "Folder data:"
echo "$FOLDER_DATA" | jq '.Item'

# UPDATE operation
echo -e "\n${YELLOW}--- UPDATE Operation ---${NC}"
UPDATED_FOLDER_NAME="updated-folder-$(generate_uuid)"

# Create a temporary JSON file for the update expression
cat > /tmp/update-expr.json << EOF
{
  ":n": {"S": "$UPDATED_FOLDER_NAME"}
}
EOF

UPDATE_RESULT=$(aws dynamodb update-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FOLDERS_TABLE \
  --key "{\"folder_id\":{\"S\":\"$FOLDER_ID\"}}" \
  --update-expression "SET folder_name = :n" \
  --expression-attribute-values file:///tmp/update-expr.json \
  --return-values "UPDATED_NEW")

echo "Updated attributes:"
echo "$UPDATE_RESULT" | jq '.Attributes'

# READ after UPDATE
echo -e "\n${YELLOW}--- READ After UPDATE ---${NC}"
UPDATED_FOLDER_DATA=$(aws dynamodb get-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FOLDERS_TABLE \
  --key "{\"folder_id\":{\"S\":\"$FOLDER_ID\"}}")

echo "Updated folder data:"
echo "$UPDATED_FOLDER_DATA" | jq '.Item'

# DELETE operation
echo -e "\n${YELLOW}--- DELETE Operation ---${NC}"
DELETE_RESULT=$(aws dynamodb delete-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FOLDERS_TABLE \
  --key "{\"folder_id\":{\"S\":\"$FOLDER_ID\"}}" \
  --return-values "ALL_OLD")

echo "Deleted folder data:"
echo "$DELETE_RESULT" | jq '.Attributes'

# READ after DELETE
echo -e "\n${YELLOW}--- READ After DELETE ---${NC}"
DELETED_FOLDER_DATA=$(aws dynamodb get-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FOLDERS_TABLE \
  --key "{\"folder_id\":{\"S\":\"$FOLDER_ID\"}}")

if [ -z "$(echo "$DELETED_FOLDER_DATA" | jq '.Item')" ] || [ "$(echo "$DELETED_FOLDER_DATA" | jq '.Item')" = "null" ]; then
  echo -e "✅ Folder $FOLDER_ID not found (expected)"
else
  echo -e "${RED}❌ Folder $FOLDER_ID still exists (unexpected)${NC}"
  exit 1
fi

# Test FilesMetaData CRUD operations
echo -e "\n${BLUE}=== Testing FilesMetaData CRUD Operations ===${NC}"

# First create a folder to reference
REF_FOLDER_ID="ref-folder-$(generate_uuid)"
aws dynamodb put-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FOLDERS_TABLE \
  --item "{\"folder_id\":{\"S\":\"$REF_FOLDER_ID\"},\"folder_path\":{\"S\":\"/ref/folder/$(generate_uuid)\"},\"folder_name\":{\"S\":\"ref-folder-$(generate_uuid)\"}}"

echo -e "Created reference folder: $REF_FOLDER_ID"

# Generate test data
FILE_ID="test-file-$(generate_uuid)"
FILE_PATH="/test/file/$(generate_uuid).txt"
FILE_NAME="test-file-$(generate_uuid).txt"
FILE_HASH="hash-$(generate_uuid)"
FILE_TYPE="text/plain"

# CREATE operation
echo -e "\n${YELLOW}--- CREATE Operation ---${NC}"
aws dynamodb put-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FILES_TABLE \
  --item "{\"file_id\":{\"S\":\"$FILE_ID\"},\"file_path\":{\"S\":\"$FILE_PATH\"},\"file_name\":{\"S\":\"$FILE_NAME\"},\"file_hash\":{\"S\":\"$FILE_HASH\"},\"file_type\":{\"S\":\"$FILE_TYPE\"},\"folder_id\":{\"S\":\"$REF_FOLDER_ID\"}}"

echo -e "✅ Successfully created file: $FILE_ID"

# READ operation
echo -e "\n${YELLOW}--- READ Operation ---${NC}"
FILE_DATA=$(aws dynamodb get-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FILES_TABLE \
  --key "{\"file_id\":{\"S\":\"$FILE_ID\"}}")

echo "File data:"
echo "$FILE_DATA" | jq '.Item'

# UPDATE operation
echo -e "\n${YELLOW}--- UPDATE Operation ---${NC}"
UPDATED_FILE_HASH="updated-hash-$(generate_uuid)"

# Create a temporary JSON file for the update expression
cat > /tmp/update-expr.json << EOF
{
  ":h": {"S": "$UPDATED_FILE_HASH"}
}
EOF

UPDATE_RESULT=$(aws dynamodb update-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FILES_TABLE \
  --key "{\"file_id\":{\"S\":\"$FILE_ID\"}}" \
  --update-expression "SET file_hash = :h" \
  --expression-attribute-values file:///tmp/update-expr.json \
  --return-values "UPDATED_NEW")

echo "Updated attributes:"
echo "$UPDATE_RESULT" | jq '.Attributes'

# READ after UPDATE
echo -e "\n${YELLOW}--- READ After UPDATE ---${NC}"
UPDATED_FILE_DATA=$(aws dynamodb get-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FILES_TABLE \
  --key "{\"file_id\":{\"S\":\"$FILE_ID\"}}")

echo "Updated file data:"
echo "$UPDATED_FILE_DATA" | jq '.Item'

# DELETE operation
echo -e "\n${YELLOW}--- DELETE Operation ---${NC}"
DELETE_RESULT=$(aws dynamodb delete-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FILES_TABLE \
  --key "{\"file_id\":{\"S\":\"$FILE_ID\"}}" \
  --return-values "ALL_OLD")

echo "Deleted file data:"
echo "$DELETE_RESULT" | jq '.Attributes'

# READ after DELETE
echo -e "\n${YELLOW}--- READ After DELETE ---${NC}"
DELETED_FILE_DATA=$(aws dynamodb get-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FILES_TABLE \
  --key "{\"file_id\":{\"S\":\"$FILE_ID\"}}")

if [ -z "$(echo "$DELETED_FILE_DATA" | jq '.Item')" ] || [ "$(echo "$DELETED_FILE_DATA" | jq '.Item')" = "null" ]; then
  echo -e "✅ File $FILE_ID not found (expected)"
else
  echo -e "${RED}❌ File $FILE_ID still exists (unexpected)${NC}"
  exit 1
fi

# Clean up the reference folder
aws dynamodb delete-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FOLDERS_TABLE \
  --key "{\"folder_id\":{\"S\":\"$REF_FOLDER_ID\"}}"

echo -e "Cleaned up reference folder: $REF_FOLDER_ID"

# Test Chunks CRUD operations
echo -e "\n${BLUE}=== Testing Chunks CRUD Operations ===${NC}"

# First create a folder and file to reference
REF_FOLDER_ID="ref-folder-$(generate_uuid)"
aws dynamodb put-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FOLDERS_TABLE \
  --item "{\"folder_id\":{\"S\":\"$REF_FOLDER_ID\"},\"folder_path\":{\"S\":\"/ref/folder/$(generate_uuid)\"},\"folder_name\":{\"S\":\"ref-folder-$(generate_uuid)\"}}"

echo -e "Created reference folder: $REF_FOLDER_ID"

REF_FILE_ID="ref-file-$(generate_uuid)"
aws dynamodb put-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FILES_TABLE \
  --item "{\"file_id\":{\"S\":\"$REF_FILE_ID\"},\"file_path\":{\"S\":\"/ref/file/$(generate_uuid).txt\"},\"file_name\":{\"S\":\"ref-file-$(generate_uuid).txt\"},\"file_hash\":{\"S\":\"hash-$(generate_uuid)\"},\"file_type\":{\"S\":\"text/plain\"},\"folder_id\":{\"S\":\"$REF_FOLDER_ID\"}}"

echo -e "Created reference file: $REF_FILE_ID"

# Generate test data
CHUNK_ID="test-chunk-$(generate_uuid)"
PART_NUMBER=1
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
FINGERPRINT="fingerprint-$(generate_uuid)"

# CREATE operation
echo -e "\n${YELLOW}--- CREATE Operation ---${NC}"
aws dynamodb put-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $CHUNKS_TABLE \
  --item "{\"chunk_id\":{\"S\":\"$CHUNK_ID\"},\"file_id\":{\"S\":\"$REF_FILE_ID\"},\"part_number\":{\"N\":\"$PART_NUMBER\"},\"created_at\":{\"S\":\"$CURRENT_TIME\"},\"fingerprint\":{\"S\":\"$FINGERPRINT\"}}"

echo -e "✅ Successfully created chunk: $CHUNK_ID"

# READ operation
echo -e "\n${YELLOW}--- READ Operation ---${NC}"
CHUNK_DATA=$(aws dynamodb get-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $CHUNKS_TABLE \
  --key "{\"chunk_id\":{\"S\":\"$CHUNK_ID\"},\"file_id\":{\"S\":\"$REF_FILE_ID\"}}")

echo "Chunk data:"
echo "$CHUNK_DATA" | jq '.Item'

# UPDATE operation
echo -e "\n${YELLOW}--- UPDATE Operation ---${NC}"
UPDATED_FINGERPRINT="updated-fingerprint-$(generate_uuid)"
LAST_SYNCED=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

# Create a temporary JSON file for the update expression
cat > /tmp/update-expr.json << EOF
{
  ":f": {"S": "$UPDATED_FINGERPRINT"},
  ":ls": {"S": "$LAST_SYNCED"}
}
EOF

UPDATE_RESULT=$(aws dynamodb update-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $CHUNKS_TABLE \
  --key "{\"chunk_id\":{\"S\":\"$CHUNK_ID\"},\"file_id\":{\"S\":\"$REF_FILE_ID\"}}" \
  --update-expression "SET fingerprint = :f, last_synced = :ls" \
  --expression-attribute-values file:///tmp/update-expr.json \
  --return-values "UPDATED_NEW")

echo "Updated attributes:"
echo "$UPDATE_RESULT" | jq '.Attributes'

# READ after UPDATE
echo -e "\n${YELLOW}--- READ After UPDATE ---${NC}"
UPDATED_CHUNK_DATA=$(aws dynamodb get-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $CHUNKS_TABLE \
  --key "{\"chunk_id\":{\"S\":\"$CHUNK_ID\"},\"file_id\":{\"S\":\"$REF_FILE_ID\"}}")

echo "Updated chunk data:"
echo "$UPDATED_CHUNK_DATA" | jq '.Item'

# DELETE operation
echo -e "\n${YELLOW}--- DELETE Operation ---${NC}"
DELETE_RESULT=$(aws dynamodb delete-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $CHUNKS_TABLE \
  --key "{\"chunk_id\":{\"S\":\"$CHUNK_ID\"},\"file_id\":{\"S\":\"$REF_FILE_ID\"}}" \
  --return-values "ALL_OLD")

echo "Deleted chunk data:"
echo "$DELETE_RESULT" | jq '.Attributes'

# READ after DELETE
echo -e "\n${YELLOW}--- READ After DELETE ---${NC}"
DELETED_CHUNK_DATA=$(aws dynamodb get-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $CHUNKS_TABLE \
  --key "{\"chunk_id\":{\"S\":\"$CHUNK_ID\"},\"file_id\":{\"S\":\"$REF_FILE_ID\"}}")

if [ -z "$(echo "$DELETED_CHUNK_DATA" | jq '.Item')" ] || [ "$(echo "$DELETED_CHUNK_DATA" | jq '.Item')" = "null" ]; then
  echo -e "✅ Chunk $CHUNK_ID not found (expected)"
else
  echo -e "${RED}❌ Chunk $CHUNK_ID still exists (unexpected)${NC}"
  exit 1
fi

# Clean up the reference file and folder
aws dynamodb delete-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FILES_TABLE \
  --key "{\"file_id\":{\"S\":\"$REF_FILE_ID\"}}"

aws dynamodb delete-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FOLDERS_TABLE \
  --key "{\"folder_id\":{\"S\":\"$REF_FOLDER_ID\"}}"

echo -e "Cleaned up reference file: $REF_FILE_ID"
echo -e "Cleaned up reference folder: $REF_FOLDER_ID"

# Test Query Operations
echo -e "\n${BLUE}=== Testing Query Operations ===${NC}"

# Create test data
QUERY_FOLDER_ID="query-test-folder-$(generate_uuid)"
aws dynamodb put-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FOLDERS_TABLE \
  --item "{\"folder_id\":{\"S\":\"$QUERY_FOLDER_ID\"},\"folder_path\":{\"S\":\"/query/folder/$(generate_uuid)\"},\"folder_name\":{\"S\":\"query-test-folder-$(generate_uuid)\"}}"

echo -e "Created query test folder: $QUERY_FOLDER_ID"

QUERY_FILE_ID="query-test-file-$(generate_uuid)"
aws dynamodb put-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FILES_TABLE \
  --item "{\"file_id\":{\"S\":\"$QUERY_FILE_ID\"},\"file_path\":{\"S\":\"/query/file/$(generate_uuid).txt\"},\"file_name\":{\"S\":\"query-test-file-$(generate_uuid).txt\"},\"file_hash\":{\"S\":\"hash-$(generate_uuid)\"},\"file_type\":{\"S\":\"text/plain\"},\"folder_id\":{\"S\":\"$QUERY_FOLDER_ID\"}}"

echo -e "Created query test file: $QUERY_FILE_ID"

# Create chunks
for i in {1..3}; do
  QUERY_CHUNK_ID="query-test-chunk-$i-$(generate_uuid)"
  CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
  
  aws dynamodb put-item \
    --endpoint-url $ENDPOINT_URL \
    --table-name $CHUNKS_TABLE \
    --item "{\"chunk_id\":{\"S\":\"$QUERY_CHUNK_ID\"},\"file_id\":{\"S\":\"$QUERY_FILE_ID\"},\"part_number\":{\"N\":\"$i\"},\"created_at\":{\"S\":\"$CURRENT_TIME\"},\"fingerprint\":{\"S\":\"fingerprint-$(generate_uuid)\"}}"
  
  echo -e "Created query test chunk $i: $QUERY_CHUNK_ID"
done

# Query chunks by file_id
echo -e "\n${YELLOW}--- Query Chunks by file_id ---${NC}"

# Create a temporary JSON file for the filter expression
cat > /tmp/filter-expr.json << EOF
{
  ":file_id": {"S": "$QUERY_FILE_ID"}
}
EOF

SCAN_RESULT=$(aws dynamodb scan \
  --endpoint-url $ENDPOINT_URL \
  --table-name $CHUNKS_TABLE \
  --filter-expression "file_id = :file_id" \
  --expression-attribute-values file:///tmp/filter-expr.json)

CHUNK_COUNT=$(echo "$SCAN_RESULT" | jq '.Count')
echo -e "Found $CHUNK_COUNT chunks for file $QUERY_FILE_ID"

echo "$SCAN_RESULT" | jq -c '.Items[] | {chunk_id: .chunk_id.S, part_number: .part_number.N}' | while read -r chunk; do
  CHUNK_ID=$(echo "$chunk" | jq -r '.chunk_id')
  PART_NUMBER=$(echo "$chunk" | jq -r '.part_number')
  echo -e "- Chunk ID: $CHUNK_ID, Part Number: $PART_NUMBER"
done

# Clean up query test data
echo -e "\n${YELLOW}--- Cleaning up query test data ---${NC}"

# Reuse the same filter expression file
SCAN_RESULT=$(aws dynamodb scan \
  --endpoint-url $ENDPOINT_URL \
  --table-name $CHUNKS_TABLE \
  --filter-expression "file_id = :file_id" \
  --expression-attribute-values file:///tmp/filter-expr.json)

echo "$SCAN_RESULT" | jq -r '.Items[] | .chunk_id.S' | while read -r chunk_id; do
  aws dynamodb delete-item \
    --endpoint-url $ENDPOINT_URL \
    --table-name $CHUNKS_TABLE \
    --key "{\"chunk_id\":{\"S\":\"$chunk_id\"},\"file_id\":{\"S\":\"$QUERY_FILE_ID\"}}"
  
  echo -e "Deleted chunk: $chunk_id"
done

aws dynamodb delete-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FILES_TABLE \
  --key "{\"file_id\":{\"S\":\"$QUERY_FILE_ID\"}}"

aws dynamodb delete-item \
  --endpoint-url $ENDPOINT_URL \
  --table-name $FOLDERS_TABLE \
  --key "{\"folder_id\":{\"S\":\"$QUERY_FOLDER_ID\"}}"

echo -e "Deleted query test file: $QUERY_FILE_ID"
echo -e "Deleted query test folder: $QUERY_FOLDER_ID"

# Clean up temporary files
rm -f /tmp/update-expr.json /tmp/filter-expr.json

# Final summary
echo -e "\n${GREEN}✅ All tests completed successfully!${NC}"
echo -e "\n${YELLOW}====================================${NC}"
echo -e "${GREEN}  DynamoDB CRUD Tests Completed   ${NC}"
echo -e "${YELLOW}====================================${NC}"

exit 0
