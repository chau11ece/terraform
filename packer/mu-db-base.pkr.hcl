# Packer template for MU Online Database Server base image
#
# What this does:
# - Starts with latest Ubuntu 22.04
# - Installs Docker (same as web)
# - Pre-pulls MSSQL Docker image (mcr.microsoft.com/mssql/server:2022-latest)
# - Creates snapshot: mu-db-base-YYYYMMDD
#
# Result: DB droplets boot in ~30 seconds instead of 2-3 minutes

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

source "digitalocean" "mu_db_base" {
  api_token     = var.do_token
  image         = "ubuntu-22-04-x64"
  region        = var.region
  size          = "s-2vcpu-4gb"
  snapshot_name = "mu-db-base-{{timestamp}}"
  ssh_username  = "root"
  tags          = ["packer", "mu-online", "db-base"]
}

build {
  sources = ["source.digitalocean.mu_db_base"]

  provisioner "shell" {
    inline = [
      "cloud-init status --wait",
      "apt-get update -qq",
      "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq"
    ]
  }

  provisioner "shell" {
    inline = [
      "echo 'Installing Docker...'",
      "apt-get install -y -qq ca-certificates curl gnupg lsb-release htop fail2ban",
      "install -m 0755 -d /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "chmod a+r /etc/apt/keyrings/docker.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "apt-get update -qq",
      "apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
      "systemctl enable docker"
    ]
  }

  provisioner "shell" {
    inline = [
      "echo 'Pre-pulling MSSQL Docker image (this takes a while)...'",
      "docker pull mcr.microsoft.com/mssql/server:2022-latest",
      "docker images"
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
    output     = "manifest-db.json"
    strip_path = true
  }
}
