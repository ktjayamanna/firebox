#!/bin/bash
#===================================================================================
# Dropbox Client E2E Test Suite Runner
#===================================================================================
# Description: This script runs all end-to-end tests for the Dropbox client.
# It executes each test script in sequence and reports the overall results.
#
# Author: Kaveen Jayamanna
# Date: May 2023
#===================================================================================

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Define constants
TEST_DIR="client/tests/e2e"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="client/tests/logs"
LOG_FILE="${LOG_DIR}/e2e_test_run_${TIMESTAMP}.log"
CONTAINER_NAME="dropbox-client"

# Create log directory if it doesn't exist
mkdir -p $LOG_DIR

# Print header
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Dropbox Client E2E Test Suite${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${CYAN}Starting test run at: $(date)${NC}"
echo -e "${CYAN}Logging to: ${LOG_FILE}${NC}\n"

# Initialize counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run a test and track results
run_test() {
    local test_name=$1
    local test_script=$2
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -e "\n${BLUE}----------------------------------------${NC}"
    echo -e "${YELLOW}Running Test: ${test_name}${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"
    
    # Run the test script and capture output
    $test_script | tee -a $LOG_FILE
    
    # Check the exit status of the test script
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "\n${GREEN}✓ Test Passed: ${test_name}${NC}" | tee -a $LOG_FILE
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "\n${RED}✗ Test Failed: ${test_name}${NC}" | tee -a $LOG_FILE
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Check if container is running
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${RED}Error: $CONTAINER_NAME container is not running${NC}"
    echo -e "Please start the container first with: ./client/scripts/bash/start_client_container.sh"
    exit 1
fi

# Make all test scripts executable
chmod +x $TEST_DIR/*.sh

# Run all tests in sequence
run_test "Core File Synchronization" "./$TEST_DIR/test_core_file_sync.sh"
run_test "File Chunking" "./$TEST_DIR/test_file_chunking.sh"
run_test "File Modifications" "./$TEST_DIR/test_file_modifications.sh"
run_test "File Deletion" "./$TEST_DIR/test_file_deletion.sh"
run_test "Move and Rename Operations" "./$TEST_DIR/test_move_rename.sh"
run_test "Folder Management" "./$TEST_DIR/test_folder_management.sh"
run_test "Content Deduplication" "./$TEST_DIR/test_content_deduplication.sh"
run_test "Large File Support" "./$TEST_DIR/test_large_file_support.sh"

# Print test summary
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Test Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${CYAN}Total Tests: ${TOTAL_TESTS}${NC}"
echo -e "${GREEN}Passed: ${PASSED_TESTS}${NC}"
echo -e "${RED}Failed: ${FAILED_TESTS}${NC}"
echo -e "${CYAN}Test run completed at: $(date)${NC}"
echo -e "${CYAN}Log file: ${LOG_FILE}${NC}"

# Return exit code based on test results
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed. Check the log file for details.${NC}"
    exit 1
fi
