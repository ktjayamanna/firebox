#!/bin/bash
set -e

# Use absolute paths to ensure everything is created in the right place
APP_DIR="/app"
DB_FILE="${APP_DIR}/data/dropbox.db"
ALEMBIC_INI="${APP_DIR}/alembic.ini"
ALEMBIC_DIR="${APP_DIR}/alembic"
ALEMBIC_ENV="${ALEMBIC_DIR}/env.py"
ALEMBIC_VERSIONS="${ALEMBIC_DIR}/versions"

# Check if database file exists
if [ ! -f "$DB_FILE" ]; then
    echo "Database file not found. Creating new database..."
    mkdir -p "${APP_DIR}/data"
    touch "$DB_FILE"
fi

# Set PYTHONPATH to include current directory for module imports
export PYTHONPATH=$PYTHONPATH:${APP_DIR}

# Check if alembic.ini exists, if not create it
if [ ! -f "$ALEMBIC_INI" ]; then
    echo "alembic.ini not found. Creating..."
    # Create a basic alembic.ini file directly instead of using alembic init
    cat > "$ALEMBIC_INI" << EOF
[alembic]
script_location = alembic
prepend_sys_path = .
sqlalchemy.url = sqlite:///./data/dropbox.db

[loggers]
keys = root,sqlalchemy,alembic

[handlers]
keys = console

[formatters]
keys = generic

[logger_root]
level = WARN
handlers = console
qualname =

[logger_sqlalchemy]
level = WARN
handlers =
qualname = sqlalchemy.engine

[logger_alembic]
level = INFO
handlers =
qualname = alembic

[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = NOTSET
formatter = generic

[formatter_generic]
format = %(levelname)-5.5s [%(name)s] %(message)s
datefmt = %H:%M:%S
EOF
    echo "Created alembic.ini file at ${ALEMBIC_INI}."
fi

# Check if alembic directory exists with env.py
if [ ! -f "$ALEMBIC_ENV" ]; then
    echo "Initializing alembic directory structure..."
    # Remove existing alembic directory if it exists
    rm -rf "$ALEMBIC_DIR"
    # Initialize alembic
    cd "$APP_DIR" && alembic init alembic
    # Update env.py to use our models
    sed -i "s|target_metadata = None|from db.models import Base\ntarget_metadata = Base.metadata|" "$ALEMBIC_ENV"
    echo "Alembic directory initialized at ${ALEMBIC_DIR}."
fi

# Check if we have any migration files
if [ -z "$(ls -A $ALEMBIC_VERSIONS 2>/dev/null)" ]; then
    echo "No migration files found. Generating initial migration..."
    cd "$APP_DIR" && alembic revision --autogenerate -m "Create initial tables"
    echo "Initial migration generated in ${ALEMBIC_VERSIONS}."
fi

# Apply all migrations
echo "Applying database migrations..."
cd "$APP_DIR" && alembic upgrade head

echo "Database setup complete."
echo "Starting FastAPI application..."
cd "$APP_DIR" && exec uvicorn server.main:app --host 0.0.0.0 --port 8000
