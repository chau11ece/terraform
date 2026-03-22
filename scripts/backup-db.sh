#!/bin/bash
# =============================================================================
# Backup MU Online databases FROM live DO droplet TO local machine
# Run this BEFORE terraform destroy to save latest game data!
# Usage: ./scripts/backup-db.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_ROOT="$SCRIPT_DIR/../backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/live_$DATE"

# Get DB IP from terraform
DB_IP=$(cd "$SCRIPT_DIR/.." && terraform output -raw db_droplet_ip 2>/dev/null)
if [ -z "$DB_IP" ] || [ "$DB_IP" = "" ]; then
  echo "ERROR: Could not get DB droplet IP from terraform output"
  echo "Make sure droplets are running: terraform output db_droplet_ip"
  exit 1
fi

# Get SA password from env
SA_PASSWORD="${TF_VAR_mu_db_password}"
if [ -z "$SA_PASSWORD" ]; then
  echo "ERROR: TF_VAR_mu_db_password not set"
  echo "Run: export TF_VAR_mu_db_password='your_password'"
  exit 1
fi

echo "============================================"
echo "Backing up MU Online databases"
echo "  Source: $DB_IP (live DO droplet)"
echo "  Dest:   $BACKUP_DIR"
echo "  Time:   $(date)"
echo "============================================"

# Databases to backup
DATABASES=("MuOnline" "Me_MuOnline" "Events" "Ranking")

# Create backup dir
mkdir -p "$BACKUP_DIR"

# Step 1: Create .bak files inside MSSQL container
echo ""
echo "[1/3] Creating database backups on droplet..."
for DB_NAME in "${DATABASES[@]}"; do
  echo "  Backing up $DB_NAME..."
  ssh -o StrictHostKeyChecking=no root@$DB_IP \
    "docker exec mssql /opt/mssql-tools18/bin/sqlcmd \
      -S localhost -U sa -P '$SA_PASSWORD' -C -Q \"
      BACKUP DATABASE [$DB_NAME]
      TO DISK = '/tmp/${DB_NAME}_${DATE}.bak'
      WITH FORMAT, COMPRESSION, NAME = '${DB_NAME} Full Backup';
    \"" || echo "  WARNING: Failed to backup $DB_NAME (may not exist)"
done

# Step 2: Copy from container to host, then download to local
echo ""
echo "[2/3] Downloading backups to local machine..."
for DB_NAME in "${DATABASES[@]}"; do
  BAK_FILE="${DB_NAME}_${DATE}.bak"
  ssh root@$DB_IP "docker cp mssql:/tmp/$BAK_FILE /tmp/$BAK_FILE 2>/dev/null" || continue
  scp root@$DB_IP:/tmp/$BAK_FILE "$BACKUP_DIR/$BAK_FILE" 2>/dev/null && \
    echo "  Downloaded: $BAK_FILE" || \
    echo "  WARNING: Failed to download $BAK_FILE"
done

# Step 3: Update the "latest" symlink
echo ""
echo "[3/3] Updating latest symlink..."
ln -sfn "$BACKUP_DIR" "$BACKUP_ROOT/latest"

# Show results
echo ""
echo "============================================"
echo "Backup complete!"
echo "============================================"
echo "Location: $BACKUP_DIR"
ls -lh "$BACKUP_DIR"/*.bak 2>/dev/null || echo "  (no .bak files found)"
echo ""
echo "Latest symlink: $BACKUP_ROOT/latest"
echo ""
echo "Safe to run: terraform destroy"
echo "============================================"
