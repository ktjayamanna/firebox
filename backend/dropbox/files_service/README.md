# Files Service

This microservice is responsible for handling file metadata and multipart upload operations.

## Features

- Receive file metadata and generate presigned URLs for multipart uploads
- Confirm successful multipart uploads and update chunk status
- Store file, folder, and chunk metadata in DynamoDB using PynamoDB
- Track folder structure for organized file storage

## API Endpoints

- `POST /files`: Receive file metadata and return presigned URLs for multipart upload
- `POST /files/confirm`: Confirm successful multipart upload and update chunk status
- `POST /folders`: Create or update folder information in the database

## Models

- `FilesMetaData`: Stores metadata about files
- `Chunks`: Stores information about file chunks
- `Folders`: Stores folder structure information
