from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from config import DATABASE_URL, DB_POOL_SIZE, DB_MAX_OVERFLOW, DB_POOL_TIMEOUT, DB_POOL_RECYCLE

# Create SQLAlchemy engine
engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False},
    pool_size=DB_POOL_SIZE,               # Default number of connections to maintain
    max_overflow=DB_MAX_OVERFLOW,         # Allow up to 10 connections beyond pool_size
    pool_timeout=DB_POOL_TIMEOUT,         # Seconds to wait before timing out on pool checkout
    pool_recycle=DB_POOL_RECYCLE          # Recycle connections after 1 hour
)

# Create SessionLocal class
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Create Base class
Base = declarative_base()

# Dependency to get DB session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
