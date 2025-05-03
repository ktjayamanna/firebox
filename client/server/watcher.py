import pyinotify
import os
import threading
from sqlalchemy.orm import Session
from db.engine import SessionLocal
from server.sync import SyncEngine
from typing import Callable, Dict, Any
from config import SYNC_DIR

class EventHandler(pyinotify.ProcessEvent):
    def __init__(self, sync_dir: str, callback: Callable = None):
        """
        Initialize the event handler

        Args:
            sync_dir: Directory to watch
            callback: Callback function to call when events occur
        """
        self.sync_dir = sync_dir
        self.callback = callback
        super().__init__()

    def process_IN_CREATE(self, event):
        """
        Handle file creation events

        Args:
            event: Inotify event
        """
        if not event.dir:
            print(f"File created: {event.pathname}")
            if self.callback:
                self.callback('create', event.pathname)

    def process_IN_MODIFY(self, event):
        """
        Handle file modification events

        Args:
            event: Inotify event
        """
        if not event.dir:
            print(f"File modified: {event.pathname}")
            if self.callback:
                self.callback('modify', event.pathname)

    def process_IN_DELETE(self, event):
        """
        Handle file deletion events

        Args:
            event: Inotify event
        """
        if not event.dir:
            print(f"File deleted: {event.pathname}")
            if self.callback:
                self.callback('delete', event.pathname)

    def process_IN_MOVED_FROM(self, event):
        """
        Handle file move from events

        Args:
            event: Inotify event
        """
        if not event.dir:
            print(f"File moved from: {event.pathname}")
            if self.callback:
                self.callback('move_from', event.pathname)

    def process_IN_MOVED_TO(self, event):
        """
        Handle file move to events

        Args:
            event: Inotify event
        """
        if not event.dir:
            print(f"File moved to: {event.pathname}")
            if self.callback:
                self.callback('move_to', event.pathname)

class Watcher:
    def __init__(self, sync_dir: str = SYNC_DIR):
        """
        Initialize the watcher

        Args:
            sync_dir: Directory to watch (defaults to SYNC_DIR from config)
        """
        self.sync_dir = sync_dir
        self.wm = pyinotify.WatchManager()
        self.handler = EventHandler(sync_dir, self.handle_event)
        self.notifier = None
        self.thread = None
        self.running = False

    def start(self):
        """
        Start watching the directory
        """
        if self.running:
            return

        # Create directory if it doesn't exist
        os.makedirs(self.sync_dir, exist_ok=True)

        # Set up inotify
        mask = pyinotify.IN_CREATE | pyinotify.IN_MODIFY | pyinotify.IN_DELETE | pyinotify.IN_MOVED_FROM | pyinotify.IN_MOVED_TO
        self.notifier = pyinotify.ThreadedNotifier(self.wm, self.handler)
        self.wm.add_watch(self.sync_dir, mask, rec=True, auto_add=True)

        # Start the notifier
        self.notifier.start()
        self.running = True
        print(f"Started watching directory: {self.sync_dir}")

    def stop(self):
        """
        Stop watching the directory
        """
        if not self.running:
            return

        # Stop the notifier
        self.notifier.stop()
        self.running = False
        print(f"Stopped watching directory: {self.sync_dir}")

    def handle_event(self, event_type: str, file_path: str):
        """
        Handle file events

        Args:
            event_type: Type of event (create, modify, delete, move_from, move_to)
            file_path: Path to the file
        """
        # Get a new database session
        db = SessionLocal()
        try:
            # Create sync engine
            sync_engine = SyncEngine(db, self.sync_dir)

            # Handle event based on type
            if event_type in ['create', 'modify']:
                # Upload file
                file_id = sync_engine.upload_file(file_path)
                print(f"Uploaded file: {file_path} with ID: {file_id}")

            # Note: Delete and move events would need additional handling

        finally:
            db.close()
