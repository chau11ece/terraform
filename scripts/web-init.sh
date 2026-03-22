#!/bin/bash
# =============================================================================
# MU Online Web Droplet Bootstrap Script
# Runs ONCE on first boot via cloud-init (user_data in Terraform)
# Terraform's templatefile() replaces variables before this reaches the droplet
# =============================================================================

set -e

exec > >(tee -a /var/log/mu-init.log) 2>&1

echo "============================================"
echo "MU Online Web Server Bootstrap"
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

# Install docker-compose standalone
curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

echo "Docker installed"

# 3. Configure firewall
echo "[3/6] Configuring firewall..."
ufw allow 22/tcp comment SSH
ufw allow ${mu_website_port}/tcp comment "MU Website"
echo y | ufw enable || true

# Fail2ban for SSH brute-force protection
systemctl enable fail2ban
systemctl start fail2ban

# 4. Setup MU Web
echo "[4/6] Setting up MU Web..."
mkdir -p /opt/mu-web
cd /opt/mu-web

# Pull the pre-built LINUX image from Docker Hub
# IMPORTANT: This must be built from Dockerfile.linux (php:8.2-apache), NOT the Windows Dockerfile
IMG="${docker_hub_username}/mu-web:latest"
echo "Pulling Docker image: $IMG"
docker pull $IMG || echo "Warning: Could not pull image — run mu-deploy after pushing the image"

# Create docker-compose.yml
cat > docker-compose.yml << COMPOSEEOF
services:
  mu-web:
    image: ${docker_hub_username}/mu-web:latest
    container_name: mu-web
    restart: always
    ports:
      - "${mu_website_port}:80"
    environment:
      - PUBLIC_IP=${mu_db_host}
      - SQL_SERVER=${mu_db_host},${mu_db_port}
      - DB_HOST=${mu_db_host}
      - DB_PORT=${mu_db_port}
      - DB_NAME=${mu_db_name}
      - DB_USER=${mu_db_user}
      - DB_PASS=${mu_db_password}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/health.php"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  default:
    name: mu-network
    external: false
COMPOSEEOF

# Create .env file (backup for env vars)
cat > .env << ENVEOF
PUBLIC_IP=${mu_db_host}
SQL_SERVER=${mu_db_host},${mu_db_port}
DB_HOST=${mu_db_host}
DB_PORT=${mu_db_port}
DB_NAME=${mu_db_name}
DB_USER=${mu_db_user}
DB_PASS=${mu_db_password}
ENVEOF
chmod 600 .env

# 5. Start the container
echo "[5/6] Starting MU Web container..."
docker-compose up -d

# 6. Create deploy helper + verify
echo "[6/6] Creating deploy helper..."
cat > /usr/local/bin/mu-deploy << 'DEPLOYEOF'
#!/bin/bash
echo "Pulling latest MU website image..."
cd /opt/mu-web
docker-compose pull
docker-compose up -d
docker-compose ps
echo "Deploy complete!"
DEPLOYEOF
chmod +x /usr/local/bin/mu-deploy

sleep 10
docker ps

echo "============================================"
echo "Bootstrap completed: $(date)"
echo "MU Web: /opt/mu-web/"
echo "Update: run 'mu-deploy'"
echo "Logs:   /var/log/mu-init.log"
echo "============================================"
