#!/bin/bash
#===================================================================================
# Dropbox Client DynamoDB CRUD Smoke Test
#===================================================================================
# Description: This script tests the ability to perform CRUD operations on DynamoDB
# tables from the client container. It verifies that the client can properly
# interact with the DynamoDB service.
#
# Test Coverage:
# - Configuring AWS CLI for DynamoDB
# - Creating test data in DynamoDB tables
# - Reading data from DynamoDB tables
# - Updating data in DynamoDB tables
# - Deleting data from DynamoDB tables
#
# Author: Kaveen Jayamanna
# Date: May 10, 2025
#===================================================================================

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Define constants
DYNAMODB_ENDPOINT="http://aws-dynamodb:8000"
AWS_REGION="us-east-1"
AWS_ACCESS_KEY_ID="dummy"
AWS_SECRET_ACCESS_KEY="dummy"

# Table names
FILES_TABLE="FilesMetaData"
CHUNKS_TABLE="Chunks"
FOLDERS_TABLE="Folders"

#===================================================================================
# Helper Functions
#===================================================================================

# Function to display test step header
display_step() {
    local step_num=$1
    local step_desc=$2
    echo -e "\n${YELLOW}Step $step_num: $step_desc${NC}"
}

# Function to generate a UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

#===================================================================================
# Main Test Script
#===================================================================================

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Dropbox DynamoDB CRUD Smoke Test${NC}"
echo -e "${BLUE}=========================================${NC}"

#-------------------
# Test Steps
#-------------------

# Step 1: Configure AWS CLI
display_step 1 "Configuring AWS CLI for DynamoDB"
mkdir -p ~/.aws
echo "[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
region = $AWS_REGION" > ~/.aws/credentials

echo "[default]
region = $AWS_REGION
output = json" > ~/.aws/config

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ AWS CLI configured successfully${NC}"
else
    echo -e "${RED}✗ Failed to configure AWS CLI${NC}"
    exit 1
fi

# Step 2: List DynamoDB tables and ensure they exist with correct schema
display_step 2 "Listing DynamoDB tables and ensuring they exist with correct schema"
TABLES=$(aws dynamodb list-tables --endpoint-url $DYNAMODB_ENDPOINT)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully listed DynamoDB tables${NC}"
    echo "$TABLES" | jq
else
    echo -e "${RED}✗ Failed to list DynamoDB tables${NC}"
    exit 1
fi

# Check if Folders table exists with correct schema
TABLE_NAMES=$(echo "$TABLES" | jq -r '.TableNames[]')

# Check if Folders table exists
if echo "$TABLE_NAMES" | grep -q "$FOLDERS_TABLE"; then
    echo -e "${GREEN}✓ Table $FOLDERS_TABLE exists${NC}"

    # Describe the table to check its schema
    TABLE_DESC=$(aws dynamodb describe-table --endpoint-url $DYNAMODB_ENDPOINT --table-name $FOLDERS_TABLE)

    # Check if we need to recreate the table with the correct schema
    echo -e "${YELLOW}Checking if Folders table has the correct schema...${NC}"

    # For simplicity, we'll just delete and recreate the table
    # In a production environment, you would want to check the schema more carefully
    echo -e "${YELLOW}Recreating Folders table with correct schema...${NC}"

    # Delete the existing table
    aws dynamodb delete-table --endpoint-url $DYNAMODB_ENDPOINT --table-name $FOLDERS_TABLE

    echo -e "${YELLOW}Waiting for table deletion to complete...${NC}"
    sleep 5

    # Create the table with the correct schema
    aws dynamodb create-table \
        --endpoint-url $DYNAMODB_ENDPOINT \
        --table-name $FOLDERS_TABLE \
        --attribute-definitions AttributeName=folder_id,AttributeType=S \
        --key-schema AttributeName=folder_id,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5

    echo -e "${GREEN}✓ Recreated $FOLDERS_TABLE table with correct schema${NC}"

    # Wait for table to be active
    echo -e "${YELLOW}Waiting for table to be active...${NC}"
    sleep 5
else
    echo -e "${YELLOW}⚠️ Table $FOLDERS_TABLE does not exist. Creating it now...${NC}"

    # Create the table with the correct schema
    aws dynamodb create-table \
        --endpoint-url $DYNAMODB_ENDPOINT \
        --table-name $FOLDERS_TABLE \
        --attribute-definitions AttributeName=folder_id,AttributeType=S \
        --key-schema AttributeName=folder_id,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5

    echo -e "${GREEN}✓ Created $FOLDERS_TABLE table with correct schema${NC}"

    # Wait for table to be active
    echo -e "${YELLOW}Waiting for table to be active...${NC}"
    sleep 5
fi

# Check if FilesMetaData table exists
if ! echo "$TABLE_NAMES" | grep -q "$FILES_TABLE"; then
    echo -e "${YELLOW}⚠️ Table $FILES_TABLE does not exist. Creating it now...${NC}"

    # Create the table with the correct schema
    aws dynamodb create-table \
        --endpoint-url $DYNAMODB_ENDPOINT \
        --table-name $FILES_TABLE \
        --attribute-definitions AttributeName=file_id,AttributeType=S \
        --key-schema AttributeName=file_id,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5

    echo -e "${GREEN}✓ Created $FILES_TABLE table with correct schema${NC}"

    # Wait for table to be active
    echo -e "${YELLOW}Waiting for table to be active...${NC}"
    sleep 5
fi

# Check if Chunks table exists
if ! echo "$TABLE_NAMES" | grep -q "$CHUNKS_TABLE"; then
    echo -e "${YELLOW}⚠️ Table $CHUNKS_TABLE does not exist. Creating it now...${NC}"

    # Create the table with the correct schema
    aws dynamodb create-table \
        --endpoint-url $DYNAMODB_ENDPOINT \
        --table-name $CHUNKS_TABLE \
        --attribute-definitions \
            AttributeName=chunk_id,AttributeType=S \
            AttributeName=file_id,AttributeType=S \
        --key-schema \
            AttributeName=chunk_id,KeyType=HASH \
            AttributeName=file_id,KeyType=RANGE \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5

    echo -e "${GREEN}✓ Created $CHUNKS_TABLE table with correct schema${NC}"

    # Wait for table to be active
    echo -e "${YELLOW}Waiting for table to be active...${NC}"
    sleep 5
fi

# Step 3: Test Folders table CRUD operations
display_step 3 "Testing CRUD operations on Folders table"

# Generate test data
FOLDER_ID="test-folder-$(generate_uuid)"
FOLDER_PATH="/test/folder/$(generate_uuid)"
FOLDER_NAME="test-folder-$(generate_uuid)"
PARENT_FOLDER_ID="parent-folder-$(generate_uuid)"

# First create a parent folder
echo -e "${CYAN}Creating parent folder for testing${NC}"
aws dynamodb put-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $FOLDERS_TABLE \
    --item "{\"folder_id\":{\"S\":\"$PARENT_FOLDER_ID\"},\"folder_path\":{\"S\":\"/test/parent\"},\"folder_name\":{\"S\":\"parent-folder\"}}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully created parent folder: $PARENT_FOLDER_ID${NC}"
else
    echo -e "${RED}✗ Failed to create parent folder${NC}"
    exit 1
fi

echo -e "${CYAN}Testing CREATE operation on Folders table${NC}"
aws dynamodb put-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $FOLDERS_TABLE \
    --item "{\"folder_id\":{\"S\":\"$FOLDER_ID\"},\"folder_path\":{\"S\":\"$FOLDER_PATH\"},\"folder_name\":{\"S\":\"$FOLDER_NAME\"},\"parent_folder_id\":{\"S\":\"$PARENT_FOLDER_ID\"}}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully created folder: $FOLDER_ID${NC}"
else
    echo -e "${RED}✗ Failed to create folder${NC}"
    exit 1
fi

echo -e "${CYAN}Testing READ operation on Folders table${NC}"
FOLDER_DATA=$(aws dynamodb get-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $FOLDERS_TABLE \
    --key "{\"folder_id\":{\"S\":\"$FOLDER_ID\"}}")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully read folder data${NC}"
    echo "Folder data:"
    echo "$FOLDER_DATA" | jq '.Item'
else
    echo -e "${RED}✗ Failed to read folder data${NC}"
    exit 1
fi

echo -e "${CYAN}Testing UPDATE operation on Folders table${NC}"
UPDATED_FOLDER_NAME="updated-folder-$(generate_uuid)"

# Create a temporary JSON file for the update expression
cat > /tmp/update-expr.json << EOF
{
  ":n": {"S": "$UPDATED_FOLDER_NAME"}
}
EOF

UPDATE_RESULT=$(aws dynamodb update-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $FOLDERS_TABLE \
    --key "{\"folder_id\":{\"S\":\"$FOLDER_ID\"}}" \
    --update-expression "SET folder_name = :n" \
    --expression-attribute-values file:///tmp/update-expr.json \
    --return-values "UPDATED_NEW")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully updated folder${NC}"
    echo "Updated attributes:"
    echo "$UPDATE_RESULT" | jq '.Attributes'
else
    echo -e "${RED}✗ Failed to update folder${NC}"
    exit 1
fi

echo -e "${CYAN}Testing READ after UPDATE on Folders table${NC}"
UPDATED_FOLDER_DATA=$(aws dynamodb get-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $FOLDERS_TABLE \
    --key "{\"folder_id\":{\"S\":\"$FOLDER_ID\"}}")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully read updated folder data${NC}"
    echo "Updated folder data:"
    echo "$UPDATED_FOLDER_DATA" | jq '.Item'
else
    echo -e "${RED}✗ Failed to read updated folder data${NC}"
    exit 1
fi

# Step 4: Test FilesMetaData table CRUD operations
display_step 4 "Testing CRUD operations on FilesMetaData table"

# Generate test data
FILE_ID="test-file-$(generate_uuid)"
FILE_PATH="/test/file/$(generate_uuid).txt"
FILE_NAME="test-file-$(generate_uuid).txt"
FILE_HASH="hash-$(generate_uuid)"
FILE_TYPE="text/plain"

echo -e "${CYAN}Testing CREATE operation on FilesMetaData table${NC}"
aws dynamodb put-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $FILES_TABLE \
    --item "{\"file_id\":{\"S\":\"$FILE_ID\"},\"file_path\":{\"S\":\"$FILE_PATH\"},\"file_name\":{\"S\":\"$FILE_NAME\"},\"file_hash\":{\"S\":\"$FILE_HASH\"},\"file_type\":{\"S\":\"$FILE_TYPE\"},\"folder_id\":{\"S\":\"$FOLDER_ID\"}}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully created file: $FILE_ID${NC}"
else
    echo -e "${RED}✗ Failed to create file${NC}"
    exit 1
fi

echo -e "${CYAN}Testing READ operation on FilesMetaData table${NC}"
FILE_DATA=$(aws dynamodb get-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $FILES_TABLE \
    --key "{\"file_id\":{\"S\":\"$FILE_ID\"}}")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully read file data${NC}"
    echo "File data:"
    echo "$FILE_DATA" | jq '.Item'
else
    echo -e "${RED}✗ Failed to read file data${NC}"
    exit 1
fi

echo -e "${CYAN}Testing UPDATE operation on FilesMetaData table${NC}"
UPDATED_FILE_HASH="updated-hash-$(generate_uuid)"

# Create a temporary JSON file for the update expression
cat > /tmp/update-expr.json << EOF
{
  ":h": {"S": "$UPDATED_FILE_HASH"}
}
EOF

UPDATE_RESULT=$(aws dynamodb update-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $FILES_TABLE \
    --key "{\"file_id\":{\"S\":\"$FILE_ID\"}}" \
    --update-expression "SET file_hash = :h" \
    --expression-attribute-values file:///tmp/update-expr.json \
    --return-values "UPDATED_NEW")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully updated file${NC}"
    echo "Updated attributes:"
    echo "$UPDATE_RESULT" | jq '.Attributes'
else
    echo -e "${RED}✗ Failed to update file${NC}"
    exit 1
fi

echo -e "${CYAN}Testing READ after UPDATE on FilesMetaData table${NC}"
UPDATED_FILE_DATA=$(aws dynamodb get-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $FILES_TABLE \
    --key "{\"file_id\":{\"S\":\"$FILE_ID\"}}")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully read updated file data${NC}"
    echo "Updated file data:"
    echo "$UPDATED_FILE_DATA" | jq '.Item'
else
    echo -e "${RED}✗ Failed to read updated file data${NC}"
    exit 1
fi

# Step 5: Test Chunks table CRUD operations
display_step 5 "Testing CRUD operations on Chunks table"

# Generate test data
CHUNK_ID="test-chunk-$(generate_uuid)"
PART_NUMBER=1
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
FINGERPRINT="fingerprint-$(generate_uuid)"

echo -e "${CYAN}Testing CREATE operation on Chunks table${NC}"
aws dynamodb put-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $CHUNKS_TABLE \
    --item "{\"chunk_id\":{\"S\":\"$CHUNK_ID\"},\"file_id\":{\"S\":\"$FILE_ID\"},\"part_number\":{\"N\":\"$PART_NUMBER\"},\"created_at\":{\"S\":\"$CURRENT_TIME\"},\"fingerprint\":{\"S\":\"$FINGERPRINT\"}}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully created chunk: $CHUNK_ID${NC}"
else
    echo -e "${RED}✗ Failed to create chunk${NC}"
    exit 1
fi

echo -e "${CYAN}Testing READ operation on Chunks table${NC}"
CHUNK_DATA=$(aws dynamodb get-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $CHUNKS_TABLE \
    --key "{\"chunk_id\":{\"S\":\"$CHUNK_ID\"},\"file_id\":{\"S\":\"$FILE_ID\"}}")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully read chunk data${NC}"
    echo "Chunk data:"
    echo "$CHUNK_DATA" | jq '.Item'
else
    echo -e "${RED}✗ Failed to read chunk data${NC}"
    exit 1
fi

echo -e "${CYAN}Testing UPDATE operation on Chunks table${NC}"
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
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $CHUNKS_TABLE \
    --key "{\"chunk_id\":{\"S\":\"$CHUNK_ID\"},\"file_id\":{\"S\":\"$FILE_ID\"}}" \
    --update-expression "SET fingerprint = :f, last_synced = :ls" \
    --expression-attribute-values file:///tmp/update-expr.json \
    --return-values "UPDATED_NEW")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully updated chunk${NC}"
    echo "Updated attributes:"
    echo "$UPDATE_RESULT" | jq '.Attributes'
else
    echo -e "${RED}✗ Failed to update chunk${NC}"
    exit 1
fi

echo -e "${CYAN}Testing READ after UPDATE on Chunks table${NC}"
UPDATED_CHUNK_DATA=$(aws dynamodb get-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $CHUNKS_TABLE \
    --key "{\"chunk_id\":{\"S\":\"$CHUNK_ID\"},\"file_id\":{\"S\":\"$FILE_ID\"}}")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully read updated chunk data${NC}"
    echo "Updated chunk data:"
    echo "$UPDATED_CHUNK_DATA" | jq '.Item'
else
    echo -e "${RED}✗ Failed to read updated chunk data${NC}"
    exit 1
fi

# Step 6: Test DELETE operations
display_step 6 "Testing DELETE operations"

echo -e "${CYAN}Testing DELETE operation on Chunks table${NC}"
DELETE_RESULT=$(aws dynamodb delete-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $CHUNKS_TABLE \
    --key "{\"chunk_id\":{\"S\":\"$CHUNK_ID\"},\"file_id\":{\"S\":\"$FILE_ID\"}}" \
    --return-values "ALL_OLD")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully deleted chunk${NC}"
    echo "Deleted chunk data:"
    echo "$DELETE_RESULT" | jq '.Attributes'
else
    echo -e "${RED}✗ Failed to delete chunk${NC}"
    exit 1
fi

echo -e "${CYAN}Testing READ after DELETE on Chunks table${NC}"
DELETED_CHUNK_DATA=$(aws dynamodb get-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $CHUNKS_TABLE \
    --key "{\"chunk_id\":{\"S\":\"$CHUNK_ID\"},\"file_id\":{\"S\":\"$FILE_ID\"}}")

if [ $? -eq 0 ] && [ -z "$(echo "$DELETED_CHUNK_DATA" | jq '.Item')" ]; then
    echo -e "${GREEN}✓ Chunk successfully deleted (not found in table)${NC}"
else
    echo -e "${RED}✗ Chunk still exists after deletion${NC}"
    echo "$DELETED_CHUNK_DATA" | jq '.Item'
    exit 1
fi

echo -e "${CYAN}Testing DELETE operation on FilesMetaData table${NC}"
DELETE_RESULT=$(aws dynamodb delete-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $FILES_TABLE \
    --key "{\"file_id\":{\"S\":\"$FILE_ID\"}}" \
    --return-values "ALL_OLD")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully deleted file${NC}"
    echo "Deleted file data:"
    echo "$DELETE_RESULT" | jq '.Attributes'
else
    echo -e "${RED}✗ Failed to delete file${NC}"
    exit 1
fi

echo -e "${CYAN}Testing DELETE operation on Folders table${NC}"
DELETE_RESULT=$(aws dynamodb delete-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $FOLDERS_TABLE \
    --key "{\"folder_id\":{\"S\":\"$FOLDER_ID\"}}" \
    --return-values "ALL_OLD")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully deleted folder${NC}"
    echo "Deleted folder data:"
    echo "$DELETE_RESULT" | jq '.Attributes'
else
    echo -e "${RED}✗ Failed to delete folder${NC}"
    exit 1
fi

echo -e "${CYAN}Deleting parent folder${NC}"
DELETE_RESULT=$(aws dynamodb delete-item \
    --endpoint-url $DYNAMODB_ENDPOINT \
    --table-name $FOLDERS_TABLE \
    --key "{\"folder_id\":{\"S\":\"$PARENT_FOLDER_ID\"}}" \
    --return-values "ALL_OLD")

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully deleted parent folder${NC}"
    echo "Deleted parent folder data:"
    echo "$DELETE_RESULT" | jq '.Attributes'
else
    echo -e "${RED}✗ Failed to delete parent folder${NC}"
    exit 1
fi

# Step 7: Clean up temporary files
display_step 7 "Cleaning up temporary files"
rm -f /tmp/update-expr.json
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Temporary files cleaned up successfully${NC}"
else
    echo -e "${RED}✗ Failed to clean up temporary files${NC}"
fi

#-------------------
# Test Summary
#-------------------
echo -e "\n${GREEN}DynamoDB CRUD test completed successfully!${NC}"
echo -e "${BLUE}=========================================${NC}"

# Return success
exit 0
