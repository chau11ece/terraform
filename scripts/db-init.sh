#!/bin/bash
# =============================================================================
# MU Online DB Droplet Bootstrap Script
# Runs ONCE on first boot via cloud-init (user_data in Terraform)
# Installs Docker and runs MSSQL Server 2022 in a container
# Data is stored on a persistent DO Volume (survives droplet destroy/recreate)
# =============================================================================

set -e

exec > >(tee -a /var/log/mu-db-init.log) 2>&1

echo "============================================"
echo "MU Online DB Server Bootstrap"
echo "Started: $(date)"
echo "============================================"

# 1. Update system
echo "[1/6] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq ca-certificates curl gnupg lsb-release htop fail2ban

# 2. Install Docker
echo "[2/6] Installing Docker..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker

echo "Docker installed: $(docker --version)"

# 3. Configure firewall
echo "[3/6] Configuring firewall..."
ufw allow 22/tcp comment SSH
ufw allow 1433/tcp comment "MSSQL"
echo y | ufw enable || true

systemctl enable fail2ban
systemctl start fail2ban

# 4. Mount persistent DO Volume
echo "[4/6] Mounting persistent volume..."
VOLUME_NAME="${volume_name}"
MOUNT_POINT="/mnt/mssql-data"
DEV_PATH="/dev/disk/by-id/scsi-0DO_Volume_$VOLUME_NAME"

# Wait for the volume device to appear (DO attaches it automatically)
for i in $(seq 1 30); do
  [ -e "$DEV_PATH" ] && break
  echo "Waiting for volume device... ($i/30)"
  sleep 2
done

if [ ! -e "$DEV_PATH" ]; then
  echo "ERROR: Volume device $DEV_PATH not found after 60s"
  exit 1
fi

# Volume is pre-formatted (initial_filesystem_type = ext4 in Terraform)
# Just mount it
mkdir -p "$MOUNT_POINT"
mount -o defaults,nofail,discard "$DEV_PATH" "$MOUNT_POINT"

# Add to fstab so it auto-mounts on reboot
grep -q "$DEV_PATH" /etc/fstab || \
  echo "$DEV_PATH $MOUNT_POINT ext4 defaults,nofail,discard 0 2" >> /etc/fstab

# Set ownership for MSSQL container (runs as UID 10001)
mkdir -p "$MOUNT_POINT/data"
chown -R 10001:0 "$MOUNT_POINT/data"

echo "Volume mounted at $MOUNT_POINT"

# 5. Run MSSQL with data on persistent volume
echo "[5/6] Starting MSSQL Server 2022..."

docker run -d \
  --name mssql \
  --restart always \
  -e "ACCEPT_EULA=Y" \
  -e "MSSQL_SA_PASSWORD=${mu_db_password}" \
  -e "MSSQL_PID=Express" \
  -p 1433:1433 \
  --memory="3g" \
  -v "$MOUNT_POINT/data:/var/opt/mssql" \
  mcr.microsoft.com/mssql/server:2022-latest

# 6. Create helper scripts
echo "[6/6] Creating helper scripts..."

cat > /usr/local/bin/mu-db-status << 'STATUSEOF'
#!/bin/bash
echo "=== MSSQL Container Status ==="
docker ps -a --filter name=mssql --format "table {{.Status}}\t{{.Ports}}"
echo ""
echo "=== Persistent Volume ==="
df -h /mnt/mssql-data
echo ""
echo "=== Memory Usage ==="
docker stats mssql --no-stream --format "table {{.MemUsage}}\t{{.MemPerc}}"
echo ""
echo "=== Recent Logs (last 20 lines) ==="
docker logs mssql --tail 20
STATUSEOF
chmod +x /usr/local/bin/mu-db-status

cat > /usr/local/bin/mu-db-connect << 'CONNECTEOF'
#!/bin/bash
# Connect to MSSQL using sqlcmd inside the container
docker exec -it mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C "$@"
CONNECTEOF
chmod +x /usr/local/bin/mu-db-connect

# Wait for MSSQL to start
echo "Waiting for MSSQL to be ready..."
sleep 15
docker ps

echo "============================================"
echo "Bootstrap completed: $(date)"
echo "MSSQL data: /mnt/mssql-data (persistent DO Volume)"
echo "Status: mu-db-status"
echo "Connect: mu-db-connect"
echo "Logs:   /var/log/mu-db-init.log"
echo "============================================"
