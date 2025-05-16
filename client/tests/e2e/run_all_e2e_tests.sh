#!/bin/bash
#===================================================================================
# Dropbox Client E2E Test Suite Runner
#===================================================================================
# Description: This script runs all the E2E tests for the Dropbox client.
# Currently, it only runs the single device tests, but it can be extended to run
# multi-device tests as well.
#===================================================================================

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Define constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SINGLE_DEVICE_DIR="${SCRIPT_DIR}/single_device"
MULTI_DEVICE_DIR="${SCRIPT_DIR}/multi_device"

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Dropbox Client E2E Test Suite${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "Starting test run at: $(date)"
echo -e "\n"

# Run single device tests
echo -e "${YELLOW}Running Single Device Tests...${NC}"
${SINGLE_DEVICE_DIR}/run_single_device_tests.sh
SINGLE_DEVICE_RESULT=$?

# Print test summary
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Test Summary${NC}"
echo -e "${BLUE}=========================================${NC}"

if [ $SINGLE_DEVICE_RESULT -eq 0 ]; then
    echo -e "Single Device Tests: ${GREEN}PASSED${NC}"
else
    echo -e "Single Device Tests: ${RED}FAILED${NC}"
fi

# Final result message
if [ $SINGLE_DEVICE_RESULT -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed!${NC}"
    exit 1
fi
