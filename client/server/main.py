from fastapi import FastAPI
import os
from contextlib import asynccontextmanager

from server.api import router as api_router
from server.watcher import Watcher
from config import SYNC_DIR, CHUNK_DIR

# Create FastAPI app
@asynccontextmanager
async def lifespan(app):
    # Start the file watcher when the application starts
    watcher.start()
    yield
    # Stop the file watcher when the application shuts down
    watcher.stop()

app = FastAPI(
    title="Dropbox Client API",
    description="API for Dropbox client synchronization",
    lifespan=lifespan
)

# Create necessary directories if they don't exist
os.makedirs(SYNC_DIR, exist_ok=True)
os.makedirs(CHUNK_DIR, exist_ok=True)
print(f"Sync directory: {SYNC_DIR}")
print(f"Chunk directory: {CHUNK_DIR}")

@app.get("/")
def read_root():
    return {"message": "Welcome to Dropbox Client API"}

@app.get("/health")
def health_check():
    return {"status": "healthy"}

# Include routers
app.include_router(api_router, prefix="/api")

# Start file watcher
watcher = Watcher()
