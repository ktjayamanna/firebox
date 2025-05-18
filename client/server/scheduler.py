"""
Background task scheduler for the client application.
This module handles periodic sync with the server every 2 minutes.
"""
import logging
import time
from datetime import datetime
import requests
from typing import Optional
import threading

# Configure logging
logger = logging.getLogger(__name__)

class SyncScheduler:
    """
    Scheduler for periodic sync with the server.
    This runs as a background task inside the FastAPI application.
    """
    def __init__(self, sync_interval: int = 120):
        """
        Initialize the scheduler.

        Args:
            sync_interval: Interval between syncs in seconds (default: 120 seconds / 2 minutes)
        """
        self.sync_interval = sync_interval
        self.running = False
        self.last_sync_time: Optional[str] = None
        self.thread: Optional[threading.Thread] = None

    def start(self):
        """
        Start the scheduler in a background thread.
        """
        if self.running:
            logger.warning("Scheduler is already running")
            return

        self.running = True
        self.thread = threading.Thread(target=self._run_sync_loop, daemon=True)
        self.thread.start()
        logger.info(f"Sync scheduler started with interval {self.sync_interval} seconds")

    def stop(self):
        """
        Stop the scheduler.
        """
        if not self.running:
            logger.warning("Scheduler is not running")
            return

        self.running = False
        if self.thread:
            self.thread.join(timeout=5)
        logger.info("Sync scheduler stopped")

    def _run_sync_loop(self):
        """
        Run the sync loop in a background thread.
        """
        logger.info("Starting sync loop")

        while self.running:
            try:
                # Call the sync endpoint
                self._sync_with_server()

                # Sleep until next sync
                logger.info(f"Sleeping for {self.sync_interval} seconds until next sync")

                # Use a loop with small sleeps to allow for faster shutdown
                for _ in range(self.sync_interval):
                    if not self.running:
                        break
                    time.sleep(1)

            except Exception as e:
                logger.error(f"Error in sync loop: {e}")
                # Sleep for a bit before retrying
                time.sleep(10)

    def _sync_with_server(self):
        """
        Call the sync endpoint to sync with the server.
        """
        try:
            logger.info(f"Syncing with server at {datetime.now().isoformat()}")

            # Call the local sync endpoint
            response = requests.post("http://localhost:8000/api/sync", json={})

            if response.status_code == 200:
                data = response.json()
                updated_files = data.get('updated_files', [])
                logger.info(f"Sync successful. {len(updated_files)} files updated.")
                self.last_sync_time = data.get('last_sync_time')
                return True
            else:
                logger.error(f"Sync failed with status code {response.status_code}: {response.text}")
                return False
        except Exception as e:
            logger.error(f"Error during sync: {e}")
            return False

# Create a singleton instance
sync_scheduler = SyncScheduler()
