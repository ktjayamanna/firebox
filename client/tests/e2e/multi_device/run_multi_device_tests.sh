#!/bin/bash
#===================================================================================
# Firebox Client Multi-Device E2E Test Suite Runner
#===================================================================================
# Description: This script runs all the multi-device E2E tests for the Firebox client.
# These tests focus on functionality that can be tested with multiple client devices
# running independently.
#===================================================================================

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Define constants
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../../logs"  # Go up two levels to reach client/tests/logs
LOG_FILE="${LOG_DIR}/multi_device_test_run_${TIMESTAMP}.log"
TEST_DIR="${SCRIPT_DIR}"
PASSED_TESTS=0
FAILED_TESTS=0
TOTAL_TESTS=0
NUM_CLIENTS=2  # Default number of clients to test

# Create log directory if it doesn't exist
mkdir -p $LOG_DIR

# Create an empty log file
touch $LOG_FILE

# Redirect all output to the log file and the terminal
exec > >(tee -a $LOG_FILE) 2>&1

# Function to run a test and track its result
run_test() {
    local test_name=$1
    local test_script=$2

    echo -e "\n${BLUE}----------------------------------------${NC}"
    echo -e "${YELLOW}Running Test: ${test_name}${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"

    # Run the test script
    $test_script
    local result=$?

    # Track the result
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ $result -eq 0 ]; then
        echo -e "\n${GREEN}✓ Test Passed: ${test_name}${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "\n${RED}✗ Test Failed: ${test_name}${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Add a separator
    echo -e "\n"

    return $result
}

# Start the test run
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Firebox Client Multi-Device E2E Test Suite${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "Starting test run at: $(date)"
echo -e "Logging to: ${LOG_FILE}"
echo -e "Number of clients: ${NUM_CLIENTS}"
echo -e "\n"

# Check if multi-client containers are running
echo -e "${YELLOW}Checking if multi-client containers are running...${NC}"
CLIENT1_RUNNING=$(docker ps | grep -q "firebox-client-1" && echo "true" || echo "false")
CLIENT2_RUNNING=$(docker ps | grep -q "firebox-client-2" && echo "true" || echo "false")

if [ "$CLIENT1_RUNNING" = "false" ] || [ "$CLIENT2_RUNNING" = "false" ]; then
    echo -e "${YELLOW}Starting multi-client containers...${NC}"
    ../../../client/scripts/bash/start_multi_client_containers.sh $NUM_CLIENTS
    
    # Wait for containers to initialize
    echo -e "${YELLOW}Waiting for containers to initialize (10 seconds)...${NC}"
    sleep 10
    
    # Check again if containers are running
    CLIENT1_RUNNING=$(docker ps | grep -q "firebox-client-1" && echo "true" || echo "false")
    CLIENT2_RUNNING=$(docker ps | grep -q "firebox-client-2" && echo "true" || echo "false")
    
    if [ "$CLIENT1_RUNNING" = "false" ] || [ "$CLIENT2_RUNNING" = "false" ]; then
        echo -e "${RED}Failed to start multi-client containers. Exiting.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Multi-client containers started successfully.${NC}"
fi

# Make all test scripts executable
chmod +x ${TEST_DIR}/*.sh

# Run all tests in sequence
run_test "Core File Synchronization" "${TEST_DIR}/test_core_file_sync.sh"
run_test "File Chunking" "${TEST_DIR}/test_file_chunking.sh"
run_test "File Modifications" "${TEST_DIR}/test_file_modifications.sh"
run_test "File Deletion" "${TEST_DIR}/test_file_deletion.sh"
run_test "Move and Rename Operations" "${TEST_DIR}/test_move_rename.sh"
run_test "Folder Management" "${TEST_DIR}/test_folder_management.sh"
run_test "Content Deduplication" "${TEST_DIR}/test_content_deduplication.sh"
run_test "Large File Support" "${TEST_DIR}/test_large_file_support.sh"
run_test "File Modification Behavior" "${TEST_DIR}/test_file_modification_behavior.sh"

# Print test summary
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Test Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "Total Tests: ${TOTAL_TESTS}"
echo -e "Passed: ${GREEN}${PASSED_TESTS}${NC}"
echo -e "Failed: ${RED}${FAILED_TESTS}${NC}"
echo -e "Test run completed at: $(date)"
echo -e "Log file: ${LOG_FILE}"

# Final result message
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed!${NC}"
    exit 1
fi
