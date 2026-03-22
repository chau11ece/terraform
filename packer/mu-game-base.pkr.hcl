# Packer template for MU Online Game Server base image
#
# What this does:
# - Starts with latest Ubuntu 22.04
# - Installs Wine (64-bit + 32-bit), Xvfb, ODBC, FreeTDS
# - Initializes Wine prefix
# - Configures FreeTDS for MSSQL 2022
# - Creates snapshot: mu-game-base-YYYYMMDD
#
# Result: Game droplets boot in ~1 minute instead of 5-7 minutes
#
# Note: Game binary files are NOT in the snapshot (too large, change often)
#       They're mounted from the persistent DO volume at runtime

packer {
  required_plugins {
    digitalocean = {
      version = ">= 1.0.0"
      source  = "github.com/digitalocean/digitalocean"
    }
  }
}

variable "do_token" {
  type      = string
  sensitive = true
  default   = env("DIGITALOCEAN_TOKEN")
}

variable "region" {
  type    = string
  default = "sgp1"
}

source "digitalocean" "mu_game_base" {
  api_token     = var.do_token
  image         = "ubuntu-22-04-x64"
  region        = var.region
  size          = "s-4vcpu-8gb"
  snapshot_name = "mu-game-base-{{timestamp}}"
  ssh_username  = "root"
  tags          = ["packer", "mu-online", "game-base"]
}

build {
  sources = ["source.digitalocean.mu_game_base"]

  provisioner "shell" {
    inline = [
      "cloud-init status --wait",
      "apt-get update -qq",
      "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq"
    ]
  }

  # Install Wine + dependencies (this is the slow part)
  provisioner "shell" {
    inline = [
      "echo 'Installing Wine and dependencies...'",
      "apt-get install -y -qq ca-certificates curl gnupg htop fail2ban net-tools",
      "dpkg --add-architecture i386",
      "apt-get update -qq",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wine64 wine32 xvfb",
      "wine --version"
    ]
  }

  # Initialize Wine prefix as root (the game runs as root via systemd)
  provisioner "shell" {
    inline = [
      "echo 'Initializing Wine prefix...'",
      "export WINEPREFIX=/root/.wine",
      "export DISPLAY=:99",
      "wineboot --init 2>/dev/null || true",
      "sleep 5",
      "ls -la /root/.wine/"
    ]
  }

  # Install ODBC + FreeTDS for database connectivity
  provisioner "shell" {
    inline = [
      "echo 'Installing ODBC + FreeTDS...'",
      "apt-get install -y -qq unixodbc tdsodbc freetds-bin freetds-dev",
      "apt-get install -y -qq tdsodbc:i386 2>/dev/null || true",
      "odbcinst -q -d"
    ]
  }

  # Configure FreeTDS for MSSQL 2022 (newer TDS version + encryption)
  provisioner "shell" {
    inline = [
      "echo 'Configuring FreeTDS...'",
      "cat > /etc/freetds/freetds.conf << 'EOF'",
      "[global]",
      "tds version = 7.4",
      "client charset = UTF-8",
      "text size = 64512",
      "encryption = request",
      "EOF",
      "cat /etc/freetds/freetds.conf"
    ]
  }

  # Register FreeTDS as SQL Server driver in ODBC
  provisioner "shell" {
    inline = [
      "echo 'Registering ODBC driver...'",
      "cat > /tmp/tdsodbc.ini << 'EOF'",
      "[SQL Server]",
      "Description = FreeTDS ODBC Driver for SQL Server",
      "Driver = /usr/lib/x86_64-linux-gnu/odbc/libtdsodbc.so",
      "Setup = /usr/lib/x86_64-linux-gnu/odbc/libtdsS.so",
      "EOF",
      "odbcinst -i -d -f /tmp/tdsodbc.ini",
      "odbcinst -q -d"
    ]
  }

  provisioner "shell" {
    inline = [
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*",
      "history -c"
    ]
  }

  post-processor "manifest" {
    output     = "manifest-game.json"
    strip_path = true
  }
}
