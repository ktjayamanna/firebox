import pyinotify
import os
from db.engine import SessionLocal
from server.sync import SyncEngine
from typing import Callable
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
        Handle file or directory creation events

        Args:
            event: Inotify event
        """
        if event.dir:
            print(f"Directory created: {event.pathname}")
            if self.callback:
                self.callback('create_dir', event.pathname)
        else:
            print(f"File created: {event.pathname}")
            if self.callback:
                self.callback('create', event.pathname)

    def process_IN_MODIFY(self, event):
        """
        Handle file modification events

        Args:
            event: Inotify event
        """
        if not event.dir:  # Directories don't have content to modify
            print(f"File modified: {event.pathname}")
            if self.callback:
                self.callback('modify', event.pathname)

    def process_IN_DELETE(self, event):
        """
        Handle file or directory deletion events

        Args:
            event: Inotify event
        """
        if event.dir:
            print(f"Directory deleted: {event.pathname}")
            if self.callback:
                self.callback('delete_dir', event.pathname)
        else:
            print(f"File deleted: {event.pathname}")
            if self.callback:
                self.callback('delete', event.pathname)

    def process_IN_MOVED_FROM(self, event):
        """
        Handle file or directory move from events

        Args:
            event: Inotify event
        """
        if event.dir:
            print(f"Directory moved from: {event.pathname}")
            if self.callback:
                self.callback('move_from_dir', event.pathname)
        else:
            print(f"File moved from: {event.pathname}")
            if self.callback:
                self.callback('move_from', event.pathname)

    def process_IN_MOVED_TO(self, event):
        """
        Handle file or directory move to events

        Args:
            event: Inotify event
        """
        if event.dir:
            print(f"Directory moved to: {event.pathname}")
            if self.callback:
                self.callback('move_to_dir', event.pathname)
        else:
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
        Start watching the directory and scan existing files
        """
        if self.running:
            return

        # Create directory if it doesn't exist
        os.makedirs(self.sync_dir, exist_ok=True)

        # Scan existing files in the sync directory
        self.scan_existing_files()

        # Set up inotify
        mask = pyinotify.IN_CREATE | pyinotify.IN_MODIFY | pyinotify.IN_DELETE | pyinotify.IN_MOVED_FROM | pyinotify.IN_MOVED_TO
        self.notifier = pyinotify.ThreadedNotifier(self.wm, self.handler)
        self.wm.add_watch(self.sync_dir, mask, rec=True, auto_add=True)

        # Start the notifier
        self.notifier.start()
        self.running = True
        print(f"Started watching directory: {self.sync_dir}")

    def scan_existing_files(self):
        """
        Scan existing files in the sync directory and process them
        """
        print(f"Scanning existing files in: {self.sync_dir}")

        # Get a new database session
        db = SessionLocal()
        try:
            # Create sync engine
            sync_engine = SyncEngine(db, self.sync_dir)

            # Scan the sync directory
            sync_engine.scan_sync_directory()

        finally:
            db.close()

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

    def handle_event(self, event_type: str, path: str):
        """
        Handle file and directory events

        Args:
            event_type: Type of event (create, modify, delete, move_from, move_to,
                        create_dir, delete_dir, move_from_dir, move_to_dir)
            path: Path to the file or directory
        """
        # Get a new database session
        db = SessionLocal()
        try:
            # Create sync engine
            sync_engine = SyncEngine(db, self.sync_dir)

            # Handle event based on type
            if event_type in ['create', 'modify']:
                # Upload file
                file_id = sync_engine.upload_file(path)
                print(f"Uploaded file: {path} with ID: {file_id}")

            elif event_type == 'create_dir':
                # Create directory entry
                dir_id = str(uuid.uuid4())
                dir_name = os.path.basename(path)
                parent_path = os.path.dirname(path)

                # Check if directory already exists in database
                existing_dir = db.query(FilesMetaData).filter(
                    FilesMetaData.file_path == path,
                    FilesMetaData.file_type == "directory"
                ).first()

                if not existing_dir:
                    # Create new directory entry
                    dir_metadata = FilesMetaData(
                        file_id=dir_id,
                        file_type="directory",
                        file_path=path,
                        parent_path=parent_path,
                        file_name=dir_name,
                        file_hash=None
                    )

                    db.add(dir_metadata)
                    db.commit()
                    print(f"Added directory to database: {path}")

            elif event_type == 'delete':
                # Delete file entry and its chunks
                file_metadata = db.query(FilesMetaData).filter(
                    FilesMetaData.file_path == path,
                    FilesMetaData.file_type != "directory"
                ).first()

                if file_metadata:
                    # Delete chunks
                    db.query(Chunks).filter(Chunks.file_id == file_metadata.file_id).delete()
                    # Delete file metadata
                    db.delete(file_metadata)
                    db.commit()
                    print(f"Deleted file from database: {path}")

            elif event_type == 'delete_dir':
                # Delete directory entry and all its contents
                dir_metadata = db.query(FilesMetaData).filter(
                    FilesMetaData.file_path == path,
                    FilesMetaData.file_type == "directory"
                ).first()

                if dir_metadata:
                    # Delete directory
                    db.delete(dir_metadata)

                    # Delete all files and subdirectories under this directory
                    for item in db.query(FilesMetaData).filter(
                        FilesMetaData.file_path.like(f"{path}/%")
                    ).all():
                        if item.file_type != "directory":
                            # Delete chunks for files
                            db.query(Chunks).filter(Chunks.file_id == item.file_id).delete()
                        db.delete(item)

                    db.commit()
                    print(f"Deleted directory and its contents from database: {path}")

            # Note: Move events would need additional handling

        finally:
            db.close()
