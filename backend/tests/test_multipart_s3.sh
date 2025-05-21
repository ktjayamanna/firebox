#!/bin/bash
# End-to-end test script for multipart uploads and downloads using presigned URLs from S3 (Minio)
# This script tests the files service API and S3 integration

set -e  # Exit immediately if a command exits with a non-zero status

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
FILES_SERVICE_URL="http://localhost:8001"
MINIO_URL="http://localhost:9000"
S3_BUCKET_NAME="firebox-chunks"
TEST_FILE_SIZE_MB=2  # Size of test file in MB
CHUNK_SIZE_MB=5       # Size of each chunk in MB

# Print header
echo -e "${YELLOW}====================================${NC}"
echo -e "${YELLOW}  S3 Multipart Upload/Download Test ${NC}"
echo -e "${YELLOW}====================================${NC}"

# Function to generate a UUID
generate_uuid() {
  python -c "import uuid; print(str(uuid.uuid4()))"
}

# Function to display a step
display_step() {
  echo -e "\n${BLUE}=== Step $1: $2 ===${NC}"
}

# Check if required commands exist
display_step 1 "Checking required dependencies"
for cmd in curl jq aws python dd; do
  if command -v $cmd >/dev/null 2>&1; then
    echo -e "✅ $cmd is installed"
  else
    echo -e "${RED}❌ $cmd is not installed. Please install it and try again.${NC}"
    exit 1
  fi
done

# Check if services are running
display_step 2 "Checking if required services are running"

# Check if files-service is running
echo -e "${YELLOW}Checking if files-service is running...${NC}"
if curl -s $FILES_SERVICE_URL/health | grep -q "healthy"; then
  echo -e "✅ Files service is running"
else
  echo -e "${RED}❌ Files service is not running. Please start it and try again.${NC}"
  echo -e "${YELLOW}You can start it with: cd deployment/backend && docker-compose up -d${NC}"
  exit 1
fi

# Check if Minio is running
echo -e "${YELLOW}Checking if Minio is running...${NC}"
if curl -s $MINIO_URL/minio/health/live >/dev/null 2>&1; then
  echo -e "✅ Minio is running"
else
  echo -e "${RED}❌ Minio is not running. Please start it and try again.${NC}"
  echo -e "${YELLOW}You can start it with: cd deployment/aws && docker-compose up -d${NC}"
  exit 1
fi

# Create a test directory
TEST_DIR="/tmp/firebox-s3-test"
mkdir -p $TEST_DIR
echo -e "Created test directory: $TEST_DIR"

# Create a test file
display_step 3 "Creating test file"
TEST_FILE="$TEST_DIR/test_file_$(generate_uuid).bin"
echo -e "Creating a ${TEST_FILE_SIZE_MB}MB test file at $TEST_FILE"
dd if=/dev/urandom of=$TEST_FILE bs=1M count=$TEST_FILE_SIZE_MB status=progress
if [ $? -eq 0 ]; then
  echo -e "✅ Test file created successfully"
  # Calculate MD5 hash of the test file for later verification
  TEST_FILE_MD5=$(md5sum $TEST_FILE | awk '{print $1}')
  echo -e "Test file MD5: $TEST_FILE_MD5"
else
  echo -e "${RED}❌ Failed to create test file${NC}"
  exit 1
fi

# Calculate number of chunks
CHUNK_COUNT=$(( ($TEST_FILE_SIZE_MB + $CHUNK_SIZE_MB - 1) / $CHUNK_SIZE_MB ))
echo -e "File will be split into $CHUNK_COUNT chunks"

# Create a folder entry in DynamoDB for testing
display_step 4 "Creating a test folder in DynamoDB"
FOLDER_ID="test-folder-$(generate_uuid)"

# Configure AWS CLI
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_DEFAULT_REGION=us-east-1
DYNAMODB_ENDPOINT="http://localhost:8002"

# Create folder in DynamoDB
aws dynamodb put-item \
  --endpoint-url $DYNAMODB_ENDPOINT \
  --table-name Folders \
  --item "{\"folder_id\":{\"S\":\"$FOLDER_ID\"},\"folder_path\":{\"S\":\"/test\"},\"folder_name\":{\"S\":\"test\"}}"

echo -e "✅ Created test folder with ID: $FOLDER_ID"

# Call the files service API to get presigned URLs
display_step 5 "Getting presigned URLs for upload"
FILE_NAME=$(basename $TEST_FILE)
FILE_PATH="/test/$FILE_NAME"
FILE_TYPE="application/octet-stream"

# Create the request payload
REQUEST_PAYLOAD="{\"file_name\":\"$FILE_NAME\",\"file_path\":\"$FILE_PATH\",\"file_type\":\"$FILE_TYPE\",\"folder_id\":\"$FOLDER_ID\",\"chunk_count\":$CHUNK_COUNT,\"file_hash\":\"$TEST_FILE_MD5\"}"

echo -e "Request payload: $REQUEST_PAYLOAD"

# Make the API call
RESPONSE=$(curl -s -X POST "$FILES_SERVICE_URL/files" \
  -H "Content-Type: application/json" \
  -d "$REQUEST_PAYLOAD")

# Check if the API call was successful
if [ $? -ne 0 ] || [ -z "$RESPONSE" ] || [[ "$RESPONSE" == *"error"* ]]; then
  echo -e "${RED}❌ Failed to get presigned URLs${NC}"
  echo -e "Response: $RESPONSE"
  exit 1
fi

# Extract file_id and presigned_urls from the response
FILE_ID=$(echo $RESPONSE | jq -r '.file_id')
PRESIGNED_URLS=$(echo $RESPONSE | jq -r '.presigned_urls')
CHUNK_IDS=$(echo $PRESIGNED_URLS | jq -r '.[].chunk_id')

echo -e "✅ Got presigned URLs for file ID: $FILE_ID"
echo -e "Number of presigned URLs: $(echo $PRESIGNED_URLS | jq -r '. | length')"

# Split the file into chunks and upload them
display_step 6 "Uploading file chunks"

# Create a temporary directory for chunks
CHUNKS_DIR="$TEST_DIR/chunks"
mkdir -p $CHUNKS_DIR

# Split the file into chunks
echo -e "Splitting file into chunks..."
split -b ${CHUNK_SIZE_MB}M $TEST_FILE "$CHUNKS_DIR/chunk_"
CHUNK_FILES=($(ls $CHUNKS_DIR/chunk_*))

echo -e "✅ Split file into ${#CHUNK_FILES[@]} chunks"

# Upload each chunk using the presigned URLs
UPLOADED_CHUNK_IDS=()
ETAGS=()

for i in "${!CHUNK_FILES[@]}"; do
  CHUNK_FILE="${CHUNK_FILES[$i]}"
  PRESIGNED_URL=$(echo $PRESIGNED_URLS | jq -r ".[$i].presigned_url")
  CHUNK_ID=$(echo $PRESIGNED_URLS | jq -r ".[$i].chunk_id")

  echo -e "Uploading chunk $((i+1))/$CHUNK_COUNT: $CHUNK_ID"

  # Upload the chunk using curl
  UPLOAD_RESPONSE=$(curl -s -X PUT -T "$CHUNK_FILE" "$PRESIGNED_URL" -D -)

  # Extract the ETag from the response headers
  ETAG=$(echo "$UPLOAD_RESPONSE" | grep -i "ETag" | awk '{print $2}' | tr -d '"\r')

  if [ -n "$ETAG" ]; then
    echo -e "✅ Uploaded chunk $((i+1)) successfully, ETag: $ETAG"
    UPLOADED_CHUNK_IDS+=("$CHUNK_ID")
    ETAGS+=("$ETAG")
  else
    echo -e "${RED}❌ Failed to upload chunk $((i+1))${NC}"
    echo -e "Response: $UPLOAD_RESPONSE"
    exit 1
  fi
done

# Confirm the upload with the files service API
display_step 7 "Confirming multipart upload"

# Create the confirmation request payload
CONFIRM_PAYLOAD="{\"file_id\":\"$FILE_ID\",\"chunk_ids\":[$(echo "${UPLOADED_CHUNK_IDS[@]}" | sed 's/ /,/g' | sed 's/^/"/g' | sed 's/$/"/g' | sed 's/,/","/g')]}"

echo -e "Confirmation payload: $CONFIRM_PAYLOAD"

# Make the API call
CONFIRM_RESPONSE=$(curl -s -X POST "$FILES_SERVICE_URL/files/confirm" \
  -H "Content-Type: application/json" \
  -d "$CONFIRM_PAYLOAD")

# Check if the API call was successful
if [ $? -ne 0 ] || [ -z "$CONFIRM_RESPONSE" ] || [[ "$CONFIRM_RESPONSE" == *"error"* ]]; then
  echo -e "${RED}❌ Failed to confirm multipart upload${NC}"
  echo -e "Response: $CONFIRM_RESPONSE"
  exit 1
fi

# Extract success status from the response
SUCCESS=$(echo $CONFIRM_RESPONSE | jq -r '.success')

if [ "$SUCCESS" == "true" ]; then
  echo -e "✅ Multipart upload confirmed successfully"
else
  echo -e "${RED}❌ Failed to confirm multipart upload${NC}"
  echo -e "Response: $CONFIRM_RESPONSE"
  exit 1
fi

# Verify the file exists in Minio
display_step 8 "Verifying file exists in Minio"

# Configure AWS CLI for S3
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_DEFAULT_REGION=us-east-1
S3_ENDPOINT="http://localhost:9000"

# Check if the file exists in S3
S3_FILE_EXISTS=$(aws s3api head-object --endpoint-url $S3_ENDPOINT --bucket $S3_BUCKET_NAME --key $FILE_ID 2>&1 || true)

if [[ "$S3_FILE_EXISTS" == *"Not Found"* ]]; then
  echo -e "${RED}❌ File not found in S3${NC}"
  exit 1
else
  echo -e "✅ File exists in S3"
fi

# Download the file from S3
display_step 9 "Downloading file from S3"
DOWNLOAD_FILE="$TEST_DIR/downloaded_file.bin"

# Generate a presigned URL for download
DOWNLOAD_URL=$(aws s3 presign --endpoint-url $S3_ENDPOINT s3://$S3_BUCKET_NAME/$FILE_ID)

echo -e "Downloading file using presigned URL: $DOWNLOAD_URL"

# Download the file using curl
curl -s "$DOWNLOAD_URL" -o "$DOWNLOAD_FILE"

if [ $? -eq 0 ]; then
  echo -e "✅ File downloaded successfully"

  # Calculate MD5 hash of the downloaded file
  DOWNLOAD_FILE_MD5=$(md5sum $DOWNLOAD_FILE | awk '{print $1}')
  echo -e "Downloaded file MD5: $DOWNLOAD_FILE_MD5"

  # Compare the hashes
  if [ "$TEST_FILE_MD5" == "$DOWNLOAD_FILE_MD5" ]; then
    echo -e "✅ File integrity verified - MD5 hashes match"
  else
    echo -e "${RED}❌ File integrity check failed - MD5 hashes do not match${NC}"
    echo -e "Original file MD5: $TEST_FILE_MD5"
    echo -e "Downloaded file MD5: $DOWNLOAD_FILE_MD5"
    exit 1
  fi
else
  echo -e "${RED}❌ Failed to download file${NC}"
  exit 1
fi

# Clean up
display_step 10 "Cleaning up"

# Delete the test file from S3
echo -e "Deleting file from S3..."
aws s3 rm --endpoint-url $S3_ENDPOINT s3://$S3_BUCKET_NAME/$FILE_ID

# Delete the test folder from DynamoDB
echo -e "Deleting test folder from DynamoDB..."
aws dynamodb delete-item \
  --endpoint-url $DYNAMODB_ENDPOINT \
  --table-name Folders \
  --key "{\"folder_id\":{\"S\":\"$FOLDER_ID\"}}"

# Delete the test files
echo -e "Deleting test files..."
rm -rf $TEST_DIR

echo -e "✅ Cleanup completed"

# Print summary
echo -e "\n${GREEN}====================================${NC}"
echo -e "${GREEN}  Test completed successfully!      ${NC}"
echo -e "${GREEN}====================================${NC}"
echo -e "File ID: $FILE_ID"
echo -e "File size: ${TEST_FILE_SIZE_MB}MB"
echo -e "Number of chunks: $CHUNK_COUNT"
echo -e "MD5 hash: $TEST_FILE_MD5"
