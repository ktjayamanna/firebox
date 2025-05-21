"""
Main application file for the Files Service.
"""
from fastapi import FastAPI
import logging

# Import utils for table creation
from utils.db import create_tables
import config
from api import router as api_router

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/tmp/files_service.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

logger.info("Files Service starting up")

logger.info("Creating DynamoDB tables if they don't exist")
create_tables()

app = FastAPI(
    title="Files Service API",
    description="API for handling file metadata and multipart uploads",
    version="0.1.0"
)

# Include API router
app.include_router(api_router)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=config.API_HOST,
        port=config.API_PORT,
        reload=True
    )
