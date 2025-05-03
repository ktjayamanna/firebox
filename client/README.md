# Dropbox Client

This is the client component of the Dropbox-like system. It provides a local synchronization service with the following features:

- File synchronization using inotify for real-time change detection
- File chunking (5MB chunks) for efficient synchronization
- SQLite database for storing file metadata and chunk information
- FastAPI server for API access

## Directory Structure

```
client/
├── alembic/            # Database migration scripts
├── db/                 # SQLite database models and connection
│   ├── engine.py       # SQLAlchemy engine and session setup
│   ├── __init__.py
│   └── models.py       # Database models
├── scripts/            # Utility scripts
│   ├── init_db.py      # Initialize the database
│   ├── test_alembic.py # Test script for Alembic
│   ├── test_api.sh     # Test the API endpoints
│   └── test_file_sync.sh # Test file synchronization
├── server/             # FastAPI server and sync logic
│   ├── api.py          # API routes
│   ├── chunker.py      # File chunking logic
│   ├── main.py         # FastAPI application
│   ├── sync.py         # Synchronization engine
│   └── watcher.py      # inotify integration
├── alembic.ini         # Alembic configuration
├── config.py           # Application configuration
└── requirements.txt    # Python dependencies
```

## Database Models

### FilesMetaData
- file_id: Primary key, unique identifier for the file
- folder_id: Identifier for the parent folder
- file_type: Type of the file

### Chunks
- chunk_id: Primary key, unique identifier for the chunk
- file_id: Foreign key to FilesMetaData
- created_at: Timestamp when the chunk was created
- last_synced: Timestamp when the chunk was last synchronized
- fingerprint: Hash of the chunk data for integrity verification

## Running the Client

The client is designed to run in a Docker container. Use the provided Docker Compose file to start the client:

```bash
cd deployment/docker
docker-compose up -d
```

This will start the client container with the FastAPI server running on port 8000.

## Testing the Client

The client comes with several testing scripts to verify its functionality:

### Testing the API

To test the API endpoints, run:

```bash
cd client/scripts
./test_api.sh
```

This script will:
1. Start the Docker container if it's not already running
2. Test the basic API endpoints (root, health, files)
3. Create a test file in the my_dropbox directory
4. Check if the file was detected and processed

### Testing File Synchronization

To test file synchronization with different file sizes, run:

```bash
cd client/scripts
./test_file_sync.sh
```

This script will:
1. Start the Docker container if it's not already running
2. Create test files of different sizes (1MB, 5MB)
3. Copy the files to the my_dropbox directory in the container
4. Check if the files are detected and added to the database
5. Test file modification
