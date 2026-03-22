#!/bin/bash
# =============================================================================
# MU Online Game Droplet Bootstrap Script
# Runs ONCE on first boot via cloud-init (user_data in Terraform)
# Installs Wine, creates systemd services for all game servers
# =============================================================================

set -e

exec > >(tee -a /var/log/mu-game-init.log) 2>&1

echo "============================================"
echo "MU Online Game Server Bootstrap"
echo "Started: $(date)"
echo "============================================"

# Templatefile variables from Terraform
DB_PRIVATE_IP="${db_private_ip}"
MU_DB_PASSWORD="${mu_db_password}"
VOLUME_NAME="${volume_name}"

# Auto-detect public IP from DO metadata API (avoids self-reference in Terraform)
PUBLIC_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
PRIVATE_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address)
echo "Public IP:  $PUBLIC_IP"
echo "Private IP: $PRIVATE_IP"
echo "DB IP:      $DB_PRIVATE_IP"

# =============================================================================
# Step 1: Install Wine
# =============================================================================
echo "[1/5] Installing Wine and dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq ca-certificates curl gnupg htop fail2ban net-tools

dpkg --add-architecture i386
apt-get update -qq
apt-get install -y -qq wine64 wine32 xvfb

# Initialize Wine prefix (suppress first-run dialogs)
export WINEPREFIX=/root/.wine
export WINEDEBUG=-all
wineboot --init 2>/dev/null || true
sleep 5

# Install FreeTDS ODBC driver for MSSQL connectivity
# Wine forwards ODBC calls to host unixODBC → FreeTDS connects to MSSQL
apt-get install -y -qq unixodbc tdsodbc freetds-bin freetds-dev
apt-get install -y -qq tdsodbc:i386 2>/dev/null || true

# Register FreeTDS as "SQL Server" ODBC driver (DataServer expects this driver name)
cat > /etc/odbcinst.ini << 'ODBCEOF'
[SQL Server]
Description = FreeTDS ODBC Driver
Driver = /usr/lib/x86_64-linux-gnu/odbc/libtdsodbc.so
Setup = /usr/lib/x86_64-linux-gnu/odbc/libtdsS.so
UsageCount = 1
ODBCEOF

# Configure FreeTDS for MSSQL 2022 (TDS 7.4, encryption support)
cat > /etc/freetds/freetds.conf << FREETDSEOF
[global]
tds version = 7.4
port = 1433
client charset = UTF-8
encryption = request
text size = 64512

[$DB_PRIVATE_IP]
host = $DB_PRIVATE_IP
port = 1433
tds version = 7.4
encryption = request
FREETDSEOF

echo "Wine installed: $(wine --version)"
echo "FreeTDS ODBC configured for MSSQL at $DB_PRIVATE_IP"

# =============================================================================
# Step 2: Mount persistent DO Volume
# =============================================================================
echo "[2/5] Mounting persistent game volume..."
MOUNT_POINT="/opt/mu-online"
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
mkdir -p "$MOUNT_POINT"
mount -o defaults,nofail,discard "$DEV_PATH" "$MOUNT_POINT"

# Add to fstab so it auto-mounts on reboot
grep -q "$DEV_PATH" /etc/fstab || \
  echo "$DEV_PATH $MOUNT_POINT ext4 defaults,nofail,discard 0 2" >> /etc/fstab

# Check if volume already has game files (redeploy) or is empty (first deploy)
if [ -d "$MOUNT_POINT/DataServer" ] && [ -f "$MOUNT_POINT/DataServer/IGCDS.ini" ]; then
  VOLUME_HAS_FILES=true
  echo "Volume has existing game files (redeploy detected)"
else
  VOLUME_HAS_FILES=false
  echo "Volume is empty (first deploy)"
  mkdir -p "$MOUNT_POINT"/{ConnectServer,DataServer,GameServerRegular,GameServerSiege,MHPServer,Data,IGCData}
fi

echo "Volume mounted at $MOUNT_POINT"

# =============================================================================
# Step 3: Create config patching script
# =============================================================================
echo "[3/5] Creating mu-game-patch-config script..."
cat > /usr/local/bin/mu-game-patch-config << 'PATCHEOF'
#!/bin/bash
# Patches all MU Online game server configs with correct IPs
# Auto-detects public IP from DO metadata, uses Terraform-provided DB IP

set -e

PUBLIC_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
PRIVATE_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address)
PATCHEOF

# Inject DB_PRIVATE_IP and MU_DB_PASSWORD into the script (these come from Terraform templatefile)
cat >> /usr/local/bin/mu-game-patch-config << EOF
DB_PRIVATE_IP="$DB_PRIVATE_IP"
MU_DB_PASSWORD="$MU_DB_PASSWORD"
EOF

cat >> /usr/local/bin/mu-game-patch-config << 'PATCHEOF'

echo "============================================"
echo "MU Online Config Patcher"
echo "Public IP:     $PUBLIC_IP"
echo "Private IP:    $PRIVATE_IP"
echo "DB Private IP: $DB_PRIVATE_IP"
echo "============================================"

BASE="/opt/mu-online"

# --- ConnectServer ---
if [ -f "$BASE/ConnectServer/IGCCS.ini" ]; then
    echo "Patching ConnectServer/IGCCS.ini..."
    sed -i "s/192\.168\.100\.96/$PUBLIC_IP/g" "$BASE/ConnectServer/IGCCS.ini"
fi

if [ -f "$BASE/ConnectServer/IGC_ServerList.xml" ]; then
    echo "Patching ConnectServer/IGC_ServerList.xml..."
    sed -i "s/192\.168\.100\.96/$PUBLIC_IP/g" "$BASE/ConnectServer/IGC_ServerList.xml"
fi

# --- DataServer ---
if [ -f "$BASE/DataServer/IGCDS.ini" ]; then
    echo "Patching DataServer/IGCDS.ini..."
    # Replace SQL Server connection string (handle both formats)
    sed -i "s/DESKTOP-DMGC5PR\\\\MSSQLSERVER01/$DB_PRIVATE_IP,1433/g" "$BASE/DataServer/IGCDS.ini"
    # Replace SQLServerName with DB IP + port (FreeTDS needs explicit port)
    sed -i "/^SQLServerName/s/=.*/= $DB_PRIVATE_IP,1433/" "$BASE/DataServer/IGCDS.ini"
    # Replace SA password (key has tabs before =)
    sed -i "/^Pass[[:space:]]/s/=.*/= $MU_DB_PASSWORD/" "$BASE/DataServer/IGCDS.ini"
    # Inter-server IPs → localhost (keys use tabs)
    sed -i "/^ConnectServerIP/s/=.*/= 127.0.0.1/" "$BASE/DataServer/IGCDS.ini"
    sed -i "/^ChatServerIP/s/=.*/= 127.0.0.1/" "$BASE/DataServer/IGCDS.ini"
fi

# --- GameServer configs (Regular and Siege) ---
for dir in GameServerRegular GameServerSiege; do
    if [ -f "$BASE/$dir/GameServer.ini" ]; then
        echo "Patching $dir/GameServer.ini..."
        # Client-facing IP → public
        sed -i "s/192\.168\.100\.96/$PUBLIC_IP/g" "$BASE/$dir/GameServer.ini"
        # Inter-server IPs → localhost (keys use tabs before =)
        sed -i '/^JoinServerIP/s/=.*/= "127.0.0.1"/' "$BASE/$dir/GameServer.ini"
        sed -i '/^DataServer1IP/s/=.*/= "127.0.0.1"/' "$BASE/$dir/GameServer.ini"
        sed -i '/^ExDBIP/s/=.*/= "127.0.0.1"/' "$BASE/$dir/GameServer.ini"
        sed -i '/^ConnectServerIP/s/=.*/= "127.0.0.1"/' "$BASE/$dir/GameServer.ini"
        sed -i '/^ChatServerIP/s/=.*/= "127.0.0.1"/' "$BASE/$dir/GameServer.ini"
    fi
done

# --- MHPServer ---
if [ -f "$BASE/MHPServer/MHPServer.ini" ]; then
    echo "Patching MHPServer/MHPServer.ini..."
    sed -i "s/192\.168\.100\.96/$PUBLIC_IP/g" "$BASE/MHPServer/MHPServer.ini"
fi

# --- MapServerInfo: internal IPs → localhost ---
if [ -f "$BASE/IGCData/IGC_MapServerInfo.xml" ]; then
    echo "Patching IGCData/IGC_MapServerInfo.xml..."
    sed -i "s/192\.168\.100\.96/127.0.0.1/g" "$BASE/IGCData/IGC_MapServerInfo.xml"
fi

# --- AllowedIPList: add game droplet private IP ---
if [ -f "$BASE/DataServer/IGC_AllowedIPList.xml" ]; then
    echo "Patching DataServer/IGC_AllowedIPList.xml..."
    # Add private IP if not already present
    if ! grep -q "$PRIVATE_IP" "$BASE/DataServer/IGC_AllowedIPList.xml"; then
        sed -i "s|</AllowedIPList>|  <IP Address=\"$PRIVATE_IP\" Name=\"GameDroplet\"/>\n</AllowedIPList>|" "$BASE/DataServer/IGC_AllowedIPList.xml"
    fi
    # Add localhost if not already present
    if ! grep -q "127.0.0.1" "$BASE/DataServer/IGC_AllowedIPList.xml"; then
        sed -i "s|</AllowedIPList>|  <IP Address=\"127.0.0.1\" Name=\"Localhost\"/>\n</AllowedIPList>|" "$BASE/DataServer/IGC_AllowedIPList.xml"
    fi
fi

echo "============================================"
echo "Config patching complete!"
echo "============================================"
PATCHEOF
chmod +x /usr/local/bin/mu-game-patch-config

# =============================================================================
# Step 4: Create systemd service units
# =============================================================================
echo "[4/5] Creating systemd services..."

# --- DataServer ---
cat > /etc/systemd/system/mu-dataserver.service << 'SVCEOF'
[Unit]
Description=MU Online DataServer (Wine)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/mu-online/DataServer
Environment=WINEPREFIX=/root/.wine
Environment=WINEDEBUG=-all
ExecStart=/usr/bin/xvfb-run -a wine IGC.DataServer.exe
Restart=on-failure
RestartSec=10
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
SVCEOF

# --- ConnectServer ---
cat > /etc/systemd/system/mu-connectserver.service << 'SVCEOF'
[Unit]
Description=MU Online ConnectServer (Wine)
After=mu-dataserver.service
Requires=mu-dataserver.service

[Service]
Type=simple
WorkingDirectory=/opt/mu-online/ConnectServer
Environment=WINEPREFIX=/root/.wine
Environment=WINEDEBUG=-all
ExecStart=/usr/bin/xvfb-run -a wine IGC.ConnectServer.exe
Restart=on-failure
RestartSec=10
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
SVCEOF

# --- GameServer Regular ---
cat > /etc/systemd/system/mu-gameserver-regular.service << 'SVCEOF'
[Unit]
Description=MU Online GameServer Regular (Wine)
After=mu-connectserver.service
Requires=mu-dataserver.service

[Service]
Type=simple
WorkingDirectory=/opt/mu-online/GameServerRegular
Environment=WINEPREFIX=/root/.wine
Environment=WINEDEBUG=-all
ExecStart=/usr/bin/xvfb-run -a wine IGC.GameServer_R.exe
Restart=on-failure
RestartSec=10
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
SVCEOF

# --- GameServer Siege ---
cat > /etc/systemd/system/mu-gameserver-siege.service << 'SVCEOF'
[Unit]
Description=MU Online GameServer Siege (Wine)
After=mu-connectserver.service
Requires=mu-dataserver.service

[Service]
Type=simple
WorkingDirectory=/opt/mu-online/GameServerSiege
Environment=WINEPREFIX=/root/.wine
Environment=WINEDEBUG=-all
ExecStart=/usr/bin/xvfb-run -a wine IGC.GameServer_C.exe
Restart=on-failure
RestartSec=10
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
SVCEOF

# --- MHPServer ---
cat > /etc/systemd/system/mu-mhpserver.service << 'SVCEOF'
[Unit]
Description=MU Online MHPServer Anti-Hack (Wine)
After=mu-connectserver.service

[Service]
Type=simple
WorkingDirectory=/opt/mu-online/MHPServer
Environment=WINEPREFIX=/root/.wine
Environment=WINEDEBUG=-all
ExecStart=/usr/bin/xvfb-run -a wine MHPServer.exe
Restart=on-failure
RestartSec=10
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload

# =============================================================================
# Step 5: Create helper scripts
# =============================================================================
echo "[5/5] Creating helper scripts..."

# --- mu-game-status ---
cat > /usr/local/bin/mu-game-status << 'STATUSEOF'
#!/bin/bash
echo "============================================"
echo "MU Online Game Server Status"
echo "============================================"
echo ""
for svc in mu-dataserver mu-connectserver mu-gameserver-regular mu-gameserver-siege mu-mhpserver; do
    status=$(systemctl is-active $svc 2>/dev/null || echo "inactive")
    printf "  %-30s %s\n" "$svc" "$status"
done
echo ""
echo "--- Listening Ports ---"
ss -tlnp | grep -E '(wine|:44405|:5590|:5696|:5599)' || echo "  No game ports listening"
echo ""
echo "--- Memory Usage ---"
free -h | head -2
echo ""
STATUSEOF
chmod +x /usr/local/bin/mu-game-status

# --- mu-game-start ---
cat > /usr/local/bin/mu-game-start << 'STARTEOF'
#!/bin/bash
echo "Starting MU Online game servers..."
echo ""

echo "[1/5] Starting DataServer..."
systemctl start mu-dataserver
sleep 10
echo "  DataServer: $(systemctl is-active mu-dataserver)"

echo "[2/5] Starting ConnectServer..."
systemctl start mu-connectserver
sleep 5
echo "  ConnectServer: $(systemctl is-active mu-connectserver)"

echo "[3/5] Starting GameServer Regular..."
systemctl start mu-gameserver-regular
sleep 5
echo "  GameServer Regular: $(systemctl is-active mu-gameserver-regular)"

echo "[4/5] Starting GameServer Siege..."
systemctl start mu-gameserver-siege
sleep 5
echo "  GameServer Siege: $(systemctl is-active mu-gameserver-siege)"

echo "[5/5] Starting MHPServer..."
systemctl start mu-mhpserver
sleep 3
echo "  MHPServer: $(systemctl is-active mu-mhpserver)"

echo ""
echo "All servers started. Run 'mu-game-status' to verify."
STARTEOF
chmod +x /usr/local/bin/mu-game-start

# --- mu-game-stop ---
cat > /usr/local/bin/mu-game-stop << 'STOPEOF'
#!/bin/bash
echo "Stopping MU Online game servers..."
systemctl stop mu-mhpserver 2>/dev/null
systemctl stop mu-gameserver-siege 2>/dev/null
systemctl stop mu-gameserver-regular 2>/dev/null
systemctl stop mu-connectserver 2>/dev/null
systemctl stop mu-dataserver 2>/dev/null
echo "All servers stopped."
STOPEOF
chmod +x /usr/local/bin/mu-game-stop

# --- mu-game-logs ---
cat > /usr/local/bin/mu-game-logs << 'LOGSEOF'
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: mu-game-logs <server>"
    echo "  Servers: dataserver, connectserver, gameserver-regular, gameserver-siege, mhpserver"
    echo "  Example: mu-game-logs dataserver"
    exit 1
fi
journalctl -u "mu-$1" -f --no-pager
LOGSEOF
chmod +x /usr/local/bin/mu-game-logs

# =============================================================================
# Configure firewall (host-level)
# =============================================================================
ufw allow 22/tcp comment "SSH"
ufw allow 44405/tcp comment "MU ConnectServer"
ufw allow 55901:55941/tcp comment "MU GameServers"
ufw allow 55999/tcp comment "MU MHPServer"
echo y | ufw enable || true

# Fail2ban for SSH brute-force protection
systemctl enable fail2ban
systemctl start fail2ban

# =============================================================================
# Auto-start on redeploy (volume already has game files)
# =============================================================================
if [ "$VOLUME_HAS_FILES" = true ]; then
  echo "============================================"
  echo "Redeploy detected — patching configs and starting servers..."
  echo "============================================"
  mu-game-patch-config
  mu-game-start
  echo ""
  echo "Bootstrap completed: $(date)"
  echo "Game servers auto-started from persistent volume."
  echo "Run 'mu-game-status' to verify."
else
  echo "============================================"
  echo "Bootstrap completed: $(date)"
  echo ""
  echo "Next steps (first deploy):"
  echo "  1. rsync game files to /opt/mu-online/"
  echo "  2. mu-game-patch-config"
  echo "  3. mu-game-start"
  echo "  4. mu-game-status"
  echo ""
fi
echo "Logs: /var/log/mu-game-init.log"
echo "============================================"
