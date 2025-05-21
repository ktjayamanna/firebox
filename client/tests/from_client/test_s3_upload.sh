#!/bin/bash
#===================================================================================
# Firebox Client S3 Upload Smoke Test
#===================================================================================
# Description: This script tests the ability to upload files directly to the S3 
# (MinIO) bucket from the client container. It verifies that the client can properly
# interact with the S3 storage service.
#
# Test Coverage:
# - Creating a test file
# - Configuring AWS CLI for MinIO
# - Uploading the file to S3
# - Verifying the file exists in S3
# - Downloading the file to verify integrity
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
S3_BUCKET_NAME="firebox-chunks"
S3_ENDPOINT="http://aws-s3:9000"
TEST_FILE_NAME="s3_test_file.txt"
TEST_FILE_CONTENT="This is a test file for S3 upload from the Firebox client."
TEST_FILE_PATH="/tmp/${TEST_FILE_NAME}"

#===================================================================================
# Helper Functions
#===================================================================================

# Function to display test step header
display_step() {
    local step_num=$1
    local step_desc=$2
    echo -e "\n${YELLOW}Step $step_num: $step_desc${NC}"
}

#===================================================================================
# Main Test Script
#===================================================================================

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Firebox S3 Upload Smoke Test${NC}"
echo -e "${BLUE}=========================================${NC}"

#-------------------
# Test Steps
#-------------------

# Step 1: Create a test file
display_step 1 "Creating a test file"
echo "$TEST_FILE_CONTENT" > $TEST_FILE_PATH
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Test file created successfully${NC}"
else
    echo -e "${RED}✗ Failed to create test file${NC}"
    exit 1
fi

# Step 2: Configure AWS CLI
display_step 2 "Configuring AWS CLI for MinIO"
mkdir -p ~/.aws
echo '[default]
aws_access_key_id = minioadmin
aws_secret_access_key = minioadmin
region = us-east-1' > ~/.aws/credentials

echo '[default]
region = us-east-1
output = json' > ~/.aws/config

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ AWS CLI configured successfully${NC}"
else
    echo -e "${RED}✗ Failed to configure AWS CLI${NC}"
    exit 1
fi

# Step 3: Upload the file to S3
display_step 3 "Uploading file to S3 (MinIO)"
UPLOAD_RESULT=$(aws s3 cp $TEST_FILE_PATH s3://$S3_BUCKET_NAME/$TEST_FILE_NAME --endpoint-url $S3_ENDPOINT)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ File uploaded successfully${NC}"
    echo -e "$UPLOAD_RESULT"
else
    echo -e "${RED}✗ Failed to upload file${NC}"
    echo -e "$UPLOAD_RESULT"
    exit 1
fi

# Step 4: Verify the file exists in S3
display_step 4 "Verifying file exists in S3"
LIST_RESULT=$(aws s3 ls s3://$S3_BUCKET_NAME/$TEST_FILE_NAME --endpoint-url $S3_ENDPOINT)
if [ $? -eq 0 ] && [[ "$LIST_RESULT" == *"$TEST_FILE_NAME"* ]]; then
    echo -e "${GREEN}✓ File exists in S3 bucket${NC}"
    echo -e "$LIST_RESULT"
else
    echo -e "${RED}✗ File not found in S3 bucket${NC}"
    echo -e "$LIST_RESULT"
    exit 1
fi

# Step 5: Download the file from S3 to verify integrity
display_step 5 "Downloading file from S3 to verify integrity"
DOWNLOAD_PATH="/tmp/downloaded_${TEST_FILE_NAME}"
rm -f $DOWNLOAD_PATH
DOWNLOAD_RESULT=$(aws s3 cp s3://$S3_BUCKET_NAME/$TEST_FILE_NAME $DOWNLOAD_PATH --endpoint-url $S3_ENDPOINT)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ File downloaded successfully${NC}"
    
    # Compare file content
    ORIGINAL_CONTENT=$(cat $TEST_FILE_PATH)
    DOWNLOADED_CONTENT=$(cat $DOWNLOAD_PATH)
    
    if [ "$ORIGINAL_CONTENT" == "$DOWNLOADED_CONTENT" ]; then
        echo -e "${GREEN}✓ File integrity verified - content matches${NC}"
    else
        echo -e "${RED}✗ File integrity check failed - content does not match${NC}"
        echo -e "Original: $ORIGINAL_CONTENT"
        echo -e "Downloaded: $DOWNLOADED_CONTENT"
        exit 1
    fi
else
    echo -e "${RED}✗ Failed to download file${NC}"
    echo -e "$DOWNLOAD_RESULT"
    exit 1
fi

# Step 6: Clean up - delete the file from S3
display_step 6 "Cleaning up - deleting file from S3"
DELETE_RESULT=$(aws s3 rm s3://$S3_BUCKET_NAME/$TEST_FILE_NAME --endpoint-url $S3_ENDPOINT)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ File deleted successfully from S3${NC}"
else
    echo -e "${RED}✗ Failed to delete file from S3${NC}"
    echo -e "$DELETE_RESULT"
fi

# Step 7: Clean up local files
display_step 7 "Cleaning up local files"
rm -f $TEST_FILE_PATH $DOWNLOAD_PATH
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Local files cleaned up successfully${NC}"
else
    echo -e "${RED}✗ Failed to clean up local files${NC}"
fi

#-------------------
# Test Summary
#-------------------
echo -e "\n${GREEN}S3 Upload test completed successfully!${NC}"
echo -e "${BLUE}=========================================${NC}"

# Return success
exit 0
