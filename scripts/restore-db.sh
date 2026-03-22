#!/bin/bash
# =============================================================================
# Auto-restore MU Online databases from backup
# Called by Terraform provisioner after DB droplet is created
# Usage: ./restore-db.sh <DB_IP> <SA_PASSWORD>
# =============================================================================

set -e

DB_IP="$1"
SA_PASSWORD="$2"
BACKUP_ROOT="$(cd "$(dirname "$0")/.." && pwd)/backups"

# Try "latest" symlink first (from backup-db.sh), fallback to SS6_ESP19
if [ -L "$BACKUP_ROOT/latest" ]; then
  # Resolve symlink to real path (fixes scp glob issue with symlinks)
  BACKUP_DIR="$(readlink "$BACKUP_ROOT/latest")"
  echo "Using latest backup: $BACKUP_DIR"
elif [ -d "$BACKUP_ROOT/SS6_ESP19" ]; then
  BACKUP_DIR="$BACKUP_ROOT/SS6_ESP19"
  echo "No latest backup found — falling back to SS6_ESP19"
else
  echo "No backup directory found — skipping restore"
  exit 0
fi

if [ -z "$DB_IP" ] || [ -z "$SA_PASSWORD" ]; then
  echo "Usage: $0 <DB_IP> <SA_PASSWORD>"
  exit 1
fi

# Check if backups exist
BAK_COUNT=$(ls "$BACKUP_DIR"/*.bak 2>/dev/null | wc -l)
if [ "$BAK_COUNT" -eq 0 ]; then
  echo "No .bak files found in $BACKUP_DIR — skipping restore"
  exit 0
fi

echo "============================================"
echo "Checking if databases need restoring..."
echo "  DB server: $DB_IP"
echo "  Backup source: $BACKUP_DIR ($BAK_COUNT .bak files)"
echo "============================================"

# Wait a bit for MSSQL to fully load databases from volume
# (MSSQL may accept connections before all DBs are loaded)
echo "Waiting 15s for MSSQL to load databases from volume..."
sleep 15

# Check if databases already exist (volume might have data from previous run)
EXISTING=$(ssh -o StrictHostKeyChecking=no root@$DB_IP \
  "docker exec mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P '$SA_PASSWORD' -C -Q \"SELECT name FROM sys.databases WHERE name = 'MuOnline'\" -h -1 -W" 2>/dev/null | tr -d '[:space:]')

if [ "$EXISTING" = "MuOnline" ]; then
  echo "MuOnline database already exists — skipping restore (volume has data)"
  echo "============================================"
  exit 0
fi

echo "MuOnline database not found — restoring from backup..."

# Upload all .bak files to DB droplet
echo "[1/3] Uploading backup files..."
for f in "$BACKUP_DIR"/*.bak; do
  scp -o StrictHostKeyChecking=no "$f" root@$DB_IP:/tmp/
  echo "  Uploaded: $(basename "$f")"
done

# Copy into MSSQL container
echo "[2/3] Copying into MSSQL container..."
ssh root@$DB_IP "for f in /tmp/*.bak; do docker cp \$f mssql:/tmp/; done"

# Restore each database — auto-detect from .bak files
echo "[3/3] Restoring databases..."

for BAK_PATH in "$BACKUP_DIR"/*.bak; do
  BAK_FILE=$(basename "$BAK_PATH")

  # Get logical file names from the backup
  FILELIST=$(ssh root@$DB_IP "docker exec mssql /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P '$SA_PASSWORD' -C \
    -Q \"RESTORE FILELISTONLY FROM DISK = '/tmp/$BAK_FILE'\" -W -s'|' -h -1" 2>/dev/null)

  LOGICAL_DATA=$(echo "$FILELIST" | grep '|D|' | head -1 | cut -d'|' -f1)
  LOGICAL_LOG=$(echo "$FILELIST" | grep '|L|' | head -1 | cut -d'|' -f1)
  DB_NAME="$LOGICAL_DATA"

  if [ -z "$DB_NAME" ] || [ -z "$LOGICAL_LOG" ]; then
    echo "  Skip: $BAK_FILE (could not read logical names)"
    continue
  fi

  echo "  Restoring $DB_NAME from $BAK_FILE..."
  ssh root@$DB_IP "docker exec mssql /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P '$SA_PASSWORD' -C -Q \"
    RESTORE DATABASE [$DB_NAME] FROM DISK = '/tmp/$BAK_FILE'
    WITH MOVE '$LOGICAL_DATA' TO '/var/opt/mssql/data/$DB_NAME.mdf',
         MOVE '$LOGICAL_LOG' TO '/var/opt/mssql/data/${DB_NAME}_log.ldf',
         REPLACE;
    \""
done

# Verify
echo ""
echo "Verifying databases..."
ssh root@$DB_IP "docker exec mssql /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P '$SA_PASSWORD' -C -Q 'SELECT name FROM sys.databases' -W"

echo "============================================"
echo "Database restore complete!"
echo "============================================"
