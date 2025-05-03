#!/bin/bash
# Script to run the Dropbox client test suite

# Set text colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Dropbox Client Test Runner${NC}"
echo -e "${BLUE}=========================================${NC}"

echo -e "${YELLOW}The test suite has been moved to client/tests/smoke/${NC}"
echo -e "${YELLOW}Redirecting to the new test runner...${NC}"
echo -e ""

# Get the project root directory
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$PROJECT_ROOT" ]; then
    # If not in a git repository, try to find the project root by looking for the client directory
    PROJECT_ROOT=$(pwd | sed 's/\(.*\/dropbox\).*/\1/')
fi

# Check if we found the project root
if [ -d "$PROJECT_ROOT/client/tests/smoke" ]; then
    cd "$PROJECT_ROOT"
    echo -e "${CYAN}Running tests from: $PROJECT_ROOT/client/tests/smoke/run_all_tests.sh${NC}"
    echo -e ""
    ./client/tests/smoke/run_all_tests.sh "$@"
else
    echo -e "${YELLOW}Could not find the test suite.${NC}"
    echo -e "${YELLOW}Please run the tests directly with:${NC}"
    echo -e "${CYAN}cd /path/to/project/root${NC}"
    echo -e "${CYAN}./client/tests/smoke/run_all_tests.sh${NC}"
fi
