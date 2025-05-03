#!/bin/bash
set -e

DB_FILE="./dropbox.db"

# Check if database file exists
if [ ! -f "$DB_FILE" ]; then
    echo "Database file not found. Creating new database..."
    touch "$DB_FILE"
fi

# Set PYTHONPATH to include current directory for module imports
export PYTHONPATH=$PYTHONPATH:.

# Initialize Alembic if not already initialized
if [ ! -d "./alembic" ]; then
    echo "Initializing Alembic..."

    # Create alembic directory
    mkdir -p ./alembic

    # Initialize alembic
    alembic init alembic

    # Update alembic.ini to use the correct database URL
    sed -i "s|sqlalchemy.url = .*|sqlalchemy.url = sqlite:///./dropbox.db|" alembic.ini

    # Update env.py to import our models
    cat > ./alembic/env.py << 'EOF'
from logging.config import fileConfig

from sqlalchemy import engine_from_config
from sqlalchemy import pool

from alembic import context

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

# Interpret the config file for Python logging.
# This line sets up loggers basically.
fileConfig(config.config_file_name)

# add your model's MetaData object here
# for 'autogenerate' support
from db.models import Base
target_metadata = Base.metadata

def run_migrations_offline():
    """Run migrations in 'offline' mode."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online():
    """Run migrations in 'online' mode."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection, target_metadata=target_metadata
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
EOF

    echo "Alembic initialized successfully."
fi

# Check if alembic versions directory exists
if [ ! -d "./alembic/versions" ]; then
    echo "Creating alembic versions directory..."
    mkdir -p ./alembic/versions
fi

# Check if we have any migration files
if [ -z "$(ls -A ./alembic/versions 2>/dev/null)" ]; then
    echo "No migration files found. Generating initial migration..."
    alembic revision --autogenerate -m "Create initial tables"
    echo "Initial migration generated."
fi

# Apply all migrations
echo "Applying database migrations..."
alembic upgrade head

echo "Database setup complete."
echo "Starting FastAPI application..."
exec uvicorn server.main:app --host 0.0.0.0 --port 8000
