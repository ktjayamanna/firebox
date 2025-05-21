import os
import socket

# Client identification
# Use the CLIENT_ID environment variable if set, otherwise use the hostname
CLIENT_ID = os.environ.get("CLIENT_ID", socket.gethostname())

# Sync directory
SYNC_DIR = os.environ.get("SYNC_DIR", "/app/my_firebox")

# Chunk storage directory (separate from sync directory)
CHUNK_DIR = os.environ.get("CHUNK_DIR", "/app/tmp/chunk")

# Database settings
DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///./firebox.db")
DB_POOL_SIZE = int(os.environ.get("DB_POOL_SIZE", 20))
DB_MAX_OVERFLOW = int(os.environ.get("DB_MAX_OVERFLOW", 10))
DB_POOL_TIMEOUT = int(os.environ.get("DB_POOL_TIMEOUT", 30))
DB_POOL_RECYCLE = int(os.environ.get("DB_POOL_RECYCLE", 3600))

# Database file path (used in scripts)
DB_FILE_PATH = os.environ.get("DB_FILE_PATH", "/app/data/firebox.db")

# Application directory
APP_DIR = os.environ.get("APP_DIR", "/app")

# Chunk size (5MB)
CHUNK_SIZE = int(os.environ.get("CHUNK_SIZE", 5 * 1024 * 1024))

# API settings
API_HOST = os.environ.get("API_HOST", "0.0.0.0")
API_PORT = int(os.environ.get("API_PORT", 8000))

# Files Service API settings
FILES_SERVICE_URL = os.environ.get("FILES_SERVICE_URL", "http://files-service:8001")
REQUEST_TIMEOUT = int(os.environ.get("REQUEST_TIMEOUT", 30))
MAX_RETRIES = int(os.environ.get("MAX_RETRIES", 3))
