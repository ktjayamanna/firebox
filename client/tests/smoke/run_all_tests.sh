#!/bin/bash
#===================================================================================
# Firebox Client Smoke Test Suite Runner
#===================================================================================
# Description: This script runs all smoke tests for the Firebox client application.
# It ensures the Docker container is running, prepares the test environment, and
# executes each test in sequence.
#
# Usage: ./client/tests/smoke/run_all_tests.sh [options]
#   Options:
#     --no-cleanup    Skip cleaning up the sync directory before tests
#     --help          Display this help message
#
# Author: Kaveen Jayamanna
# Date: May 3, 2025
#===================================================================================

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default settings
DO_CLEANUP=true
CONTAINER_NAME="firebox-client-1"
SYNC_DIR="/app/my_firebox"
TEST_DIR="client/tests/smoke"

# Process command line arguments
for arg in "$@"; do
  case $arg in
    --no-cleanup)
      DO_CLEANUP=false
      shift
      ;;
    --help)
      echo -e "${CYAN}Firebox Client Smoke Test Suite Runner${NC}"
      echo -e "Usage: ./client/tests/smoke/run_all_tests.sh [options]"
      echo -e "  Options:"
      echo -e "    --no-cleanup    Skip cleaning up the sync directory before tests"
      echo -e "    --help          Display this help message"
      exit 0
      ;;
    *)
      # Unknown option
      echo -e "${RED}Unknown option: $arg${NC}"
      echo -e "Use --help for usage information"
      exit 1
      ;;
  esac
done

#===================================================================================
# Main Test Execution
#===================================================================================

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Running All Firebox Smoke Tests${NC}"
echo -e "${BLUE}=========================================${NC}"

#-------------------
# Container Check
#-------------------
echo -e "${YELLOW}Checking Docker container status...${NC}"
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${YELLOW}Container '$CONTAINER_NAME' is not running. Starting it now...${NC}"
    ./client/scripts/bash/start_client_container.sh

    # Wait for container to start and initialize
    echo -e "${YELLOW}Waiting for container to start and initialize (10 seconds)...${NC}"
    sleep 10

    if ! docker ps | grep -q $CONTAINER_NAME; then
        echo -e "${RED}Failed to start container. Please check docker logs:${NC}"
        echo -e "${RED}  docker logs $CONTAINER_NAME${NC}"
        exit 1
    fi
    echo -e "${GREEN}Container started successfully!${NC}"
else
    echo -e "${GREEN}Container '$CONTAINER_NAME' is already running.${NC}"
fi

#-------------------
# Test Preparation
#-------------------
# Make all test scripts executable
echo -e "${YELLOW}Ensuring test scripts are executable...${NC}"
chmod +x $TEST_DIR/test_*.sh

# Clean up the sync directory before running tests if cleanup is enabled
if [ "$DO_CLEANUP" = true ]; then
    echo -e "\n${YELLOW}Cleaning up sync directory...${NC}"
    docker exec $CONTAINER_NAME bash -c "rm -rf $SYNC_DIR/*"
    echo -e "${GREEN}Sync directory cleaned${NC}"

    # Wait for cleanup to be processed
    sleep 2
else
    echo -e "\n${YELLOW}Skipping sync directory cleanup (--no-cleanup flag used)${NC}"
fi

#-------------------
# Test Execution
#-------------------
# Run each test script with proper headers and separation
run_test() {
    local test_name=$1
    local test_script=$2

    echo -e "\n${BLUE}=========================================${NC}"
    echo -e "${YELLOW}Running $test_name...${NC}"
    echo -e "${BLUE}=========================================${NC}"

    $test_script

    # Check if the test was successful
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $test_name completed successfully${NC}"
    else
        echo -e "${RED}✗ $test_name failed${NC}"
    fi
}

# Run all tests in sequence
run_test "File Sync Test" "./$TEST_DIR/test_file_sync.sh"
run_test "File Modifications Test" "./$TEST_DIR/test_file_modifications.sh"
run_test "Folder Operations Test" "./$TEST_DIR/test_folder_operations.sh"
run_test "API Endpoints Test" "./$TEST_DIR/test_api_endpoints.sh"

#-------------------
# Test Summary
#-------------------
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}All smoke tests completed!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${CYAN}For detailed test logs, check the output above.${NC}"
echo -e "${CYAN}To run individual tests, use:${NC}"
echo -e "${CYAN}  ./$TEST_DIR/test_file_sync.sh${NC}"
echo -e "${CYAN}  ./$TEST_DIR/test_file_modifications.sh${NC}"
echo -e "${CYAN}  ./$TEST_DIR/test_folder_operations.sh${NC}"
echo -e "${CYAN}  ./$TEST_DIR/test_api_endpoints.sh${NC}"
