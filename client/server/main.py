from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session
from db.engine import get_db
from db.models import FilesMetaData, Chunks
import os
import threading

# Create FastAPI app
app = FastAPI(title="Dropbox Client API", description="API for Dropbox client synchronization")

# Create my_dropbox directory if it doesn't exist
os.makedirs("/app/my_dropbox", exist_ok=True)

@app.get("/")
def read_root():
    return {"message": "Welcome to Dropbox Client API"}

@app.get("/health")
def health_check():
    return {"status": "healthy"}

# Import routes
from server.api import router as api_router
from server.watcher import Watcher

# Include routers
app.include_router(api_router, prefix="/api")

# Start file watcher
watcher = Watcher()

@app.on_event("startup")
def startup_event():
    """Start the file watcher when the application starts"""
    watcher.start()

@app.on_event("shutdown")
def shutdown_event():
    """Stop the file watcher when the application shuts down"""
    watcher.stop()
