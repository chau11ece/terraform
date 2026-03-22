# Packer template for MU Online Web Server base image
#
# What this does:
# - Starts with latest Ubuntu 22.04
# - Installs Docker, docker-compose plugin, fail2ban, htop
# - Pre-pulls the MU web Docker image (chaudevops/mu-web:latest)
# - Creates snapshot: mu-web-base-YYYYMMDD
#
# Result: Web droplets boot in ~30 seconds instead of 2-3 minutes
#
# Build: packer build -var 'do_token=YOUR_TOKEN' mu-web-base.pkr.hcl

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

variable "docker_hub_username" {
  type    = string
  default = "chaudevops"
}

source "digitalocean" "mu_web_base" {
  api_token     = var.do_token
  image         = "ubuntu-22-04-x64"
  region        = var.region
  size          = "s-1vcpu-1gb"
  snapshot_name = "mu-web-base-{{timestamp}}"
  ssh_username  = "root"

  # Tags for organization (shows up in DO console)
  tags = ["packer", "mu-online", "web-base"]
}

build {
  sources = ["source.digitalocean.mu_web_base"]

  # Wait for cloud-init to finish (DO's default setup)
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init...'",
      "cloud-init status --wait",
      "echo 'Updating packages...'",
      "apt-get update -qq",
      "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq"
    ]
  }

  # Install Docker (official method)
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
      "systemctl enable docker",
      "docker --version"
    ]
  }

  # Pre-pull the web image (saves 30-60s on first boot)
  provisioner "shell" {
    inline = [
      "echo 'Pre-pulling MU web Docker image...'",
      "docker pull ${var.docker_hub_username}/mu-web:latest || echo 'Warning: Could not pre-pull image'",
      "docker images"
    ]
  }

  # Cleanup to reduce snapshot size
  provisioner "shell" {
    inline = [
      "echo 'Cleaning up...'",
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "rm -rf /tmp/*",
      "rm -rf /var/tmp/*",
      "history -c"
    ]
  }

  post-processor "manifest" {
    output     = "manifest-web.json"
    strip_path = true
  }
}
