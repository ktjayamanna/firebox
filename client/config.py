import os

# Sync directory
SYNC_DIR = os.environ.get("SYNC_DIR", "/app/my_dropbox")

# Chunk storage directory (separate from sync directory)
CHUNK_DIR = os.environ.get("CHUNK_DIR", "/tmp/dropbox/chunk")

# Database settings
DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///./dropbox.db")

# Chunk size (5MB)
CHUNK_SIZE = int(os.environ.get("CHUNK_SIZE", 5 * 1024 * 1024))

# API settings
API_HOST = os.environ.get("API_HOST", "0.0.0.0")
API_PORT = int(os.environ.get("API_PORT", 8000))
