# =============================================================================
# Compute Module - Main
# Handles Web and Game droplets
# =============================================================================

terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.34"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "digitalocean_ssh_key" "deploy_key" {
  name = var.ssh_key_name
}

data "digitalocean_images" "ubuntu" {
  filter {
    key    = "distribution"
    values = ["Ubuntu"]
  }
  filter {
    key    = "status"
    values = ["available"]
  }
  sort {
    key       = "created"
    direction = "desc"
  }
}

# -----------------------------------------------------------------------------
# Game Data Volume
# -----------------------------------------------------------------------------
resource "digitalocean_volume" "game_data" {
  region                  = var.region
  name                    = "${var.project_name}-game-data"
  size                    = var.game_volume_size
  initial_filesystem_type = "ext4"
  description             = "Persistent game server files"

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Web Droplets
# -----------------------------------------------------------------------------
resource "digitalocean_droplet" "web" {
  count = var.web_droplet_count

  name     = "${var.project_name}-web-${var.environment}-${count.index}"
  image    = var.web_droplet_image
  size     = var.web_droplet_size
  region   = var.region
  vpc_uuid = var.vpc_uuid
  ssh_keys = [data.digitalocean_ssh_key.deploy_key.id]

  user_data = templatefile("${path.module}/scripts/web-init.sh", {
    mu_db_host           = var.db_private_ip,
    mu_db_port           = var.mu_db_port,
    mu_db_name           = var.mu_db_name,
    mu_db_user           = var.mu_db_user,
    mu_db_password       = var.mu_db_password,
    mu_website_port      = var.mu_website_port,
    environment          = var.environment,
    public_ip            = var.db_private_ip,
    db_host              = var.db_private_ip,
    db_port              = var.mu_db_port,
    db_name              = var.mu_db_name,
    db_user              = var.mu_db_user,
    db_pass              = var.mu_db_password,
    docker_hub_username  = var.docker_hub_username,
  })

  tags = [
    var.project_name,
    var.web_tag_name,
    var.environment
  ]

  lifecycle {
    prevent_destroy = false
  }
}

# -----------------------------------------------------------------------------
# Game Droplets
# -----------------------------------------------------------------------------
resource "digitalocean_droplet" "game" {
  count = var.enable_game_server ? 1 : 0

  name       = "${var.project_name}-game-${var.environment}"
  image      = var.web_droplet_image
  size       = var.game_droplet_size
  region     = var.region
  vpc_uuid   = var.vpc_uuid
  ssh_keys   = [data.digitalocean_ssh_key.deploy_key.id]
  volume_ids = [digitalocean_volume.game_data.id]

  user_data = templatefile("${path.module}/scripts/game-init.sh", {
    db_private_ip  = var.db_private_ip,
    mu_db_password = var.mu_db_password,
    volume_name    = digitalocean_volume.game_data.name,
  })

  tags = [
    var.project_name,
    var.game_tag_name,
    var.environment
  ]

  lifecycle {
    prevent_destroy = false
  }
}
