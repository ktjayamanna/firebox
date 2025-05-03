import os
import hashlib
from typing import List, Dict, Any, Generator, Tuple

class Chunker:
    def __init__(self, chunk_size: int = 5 * 1024 * 1024):
        """
        Initialize the chunker
        
        Args:
            chunk_size: Size of each chunk in bytes (default: 5MB)
        """
        self.chunk_size = chunk_size
    
    def split_file(self, file_path: str) -> Generator[Tuple[bytes, str], None, None]:
        """
        Split a file into chunks
        
        Args:
            file_path: Path to the file to split
            
        Yields:
            Tuple of (chunk_data, fingerprint)
        """
        with open(file_path, 'rb') as f:
            while True:
                chunk_data = f.read(self.chunk_size)
                if not chunk_data:
                    break
                
                # Calculate fingerprint (hash) of chunk
                fingerprint = hashlib.sha256(chunk_data).hexdigest()
                
                yield (chunk_data, fingerprint)
    
    def merge_chunks(self, chunks: List[bytes], output_path: str) -> bool:
        """
        Merge chunks into a single file
        
        Args:
            chunks: List of chunk data
            output_path: Path to save the merged file
            
        Returns:
            bool: True if merge was successful, False otherwise
        """
        try:
            with open(output_path, 'wb') as f:
                for chunk in chunks:
                    f.write(chunk)
            return True
        except Exception as e:
            print(f"Error merging chunks: {e}")
            return False
    
    def calculate_fingerprint(self, data: bytes) -> str:
        """
        Calculate fingerprint (hash) of data
        
        Args:
            data: Data to calculate fingerprint for
            
        Returns:
            str: Fingerprint of data
        """
        return hashlib.sha256(data).hexdigest()
