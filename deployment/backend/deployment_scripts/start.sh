#!/bin/bash
set -e

# Use environment variables or defaults
APP_DIR="${APP_DIR:-/app}"

# Create a temporary directory for any processing if needed
TMP_DIR="${APP_DIR}/tmp"
mkdir -p "${TMP_DIR}"

# Clean up temporary files to prevent disk bloat
echo "Cleaning up temporary files..."
rm -rf "${TMP_DIR:?}"/*

echo "Starting FastAPI application..."
exec uvicorn main:app --host 0.0.0.0 --port 8001
