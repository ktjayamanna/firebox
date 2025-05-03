# Dropbox Client Scripts

This directory contains utility scripts for the Dropbox client.

## Database Scripts

- `init_db.py`: Initialize the SQLite database by creating all tables
- `test_alembic.py`: Test script for Alembic database migrations

## Testing Scripts

- `test_api.sh`: Test the FastAPI endpoints of the Dropbox client
- `test_file_sync.sh`: Test file synchronization with different file sizes

## Usage

### Testing the API

To test the API endpoints, run:

```bash
./test_api.sh
```

This script will:
1. Start the Docker container if it's not already running
2. Test the basic API endpoints (root, health, files)
3. Create a test file in the my_dropbox directory
4. Check if the file was detected and processed
5. Optionally stop the container when done

### Testing File Synchronization

To test file synchronization with different file sizes, run:

```bash
./test_file_sync.sh
```

This script will:
1. Start the Docker container if it's not already running
2. Create test files of different sizes (1MB, 5MB)
3. Copy the files to the my_dropbox directory in the container
4. Check if the files are detected and added to the database
5. Test file modification
6. Clean up the test files
7. Optionally stop the container when done

## Database Initialization

To initialize the database, run:

```bash
python init_db.py
```

## Testing Alembic

To test Alembic database migrations, run:

```bash
python test_alembic.py
```
