# Files Service

This microservice is responsible for handling file metadata and multipart upload operations.

## Features

- Receive file metadata and generate presigned URLs for multipart uploads
- Confirm successful multipart uploads and update chunk status
- Store file and chunk metadata in DynamoDB using PynamoDB

## API Endpoints

- `POST /files`: Receive file metadata and return presigned URLs for multipart upload
- `POST /files/confirm`: Confirm successful multipart upload and update chunk status

## Models

- `FilesMetaData`: Stores metadata about files
- `Chunks`: Stores information about file chunks
