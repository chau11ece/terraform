# =============================================================================
# Dev Environment - Main
# Uses modules to create infrastructure
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.34"
    }
  }
}

# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------
provider "digitalocean" {
  token = var.do_token
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "digitalocean_vpc" "default" {
  region = var.region
}

data "digitalocean_account" "current" {}

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
# Packer-built Custom Images (optional - set use_custom_images = true to enable)
# -----------------------------------------------------------------------------
variable "use_custom_images" {
  description = "Use Packer-built custom images instead of Ubuntu"
  type        = bool
  default     = false
}

# Custom snapshot data sources
data "digitalocean_image" "mu_web_base" {
  count = var.use_custom_images ? 1 : 0
  name  = "mu-web-base-*"
}

data "digitalocean_image" "mu_db_base" {
  count = var.use_custom_images ? 1 : 0
  name  = "mu-db-base-*"
}

data "digitalocean_image" "mu_game_base" {
  count = var.use_custom_images ? 1 : 0
  name  = "mu-game-base-*"
}

# Compute the image to use based on flag
locals {
  web_image  = var.use_custom_images ? data.digitalocean_image.mu_web_base[0].id : var.web_droplet_image
  db_image   = var.use_custom_images ? data.digitalocean_image.mu_db_base[0].id : var.web_droplet_image
  game_image = var.use_custom_images ? data.digitalocean_image.mu_game_base[0].id : var.web_droplet_image
}

# -----------------------------------------------------------------------------
# Tags (must exist before firewalls reference them)
# -----------------------------------------------------------------------------
resource "digitalocean_tag" "roles" {
  for_each = toset(["web", "db", "game"])
  name     = each.value
}

# -----------------------------------------------------------------------------
# Module: Database (creates DB droplet first - needed by web)
# -----------------------------------------------------------------------------
module "database" {
  source = "../../modules/database"

  project_name         = var.project_name
  environment          = var.environment
  region               = var.region
  ssh_key_name         = var.ssh_key_name
  vpc_uuid             = data.digitalocean_vpc.default.id
  db_tag_name          = digitalocean_tag.roles["db"].name
  db_droplet_size      = var.db_droplet_size
  db_volume_size       = var.db_volume_size
  droplet_image       = local.db_image
  mu_db_password       = var.mu_db_password
  enable_provisioners  = var.enable_provisioners
}

# -----------------------------------------------------------------------------
# Module: Compute (Web and Game droplets)
# -----------------------------------------------------------------------------
module "compute" {
  source = "../../modules/compute"

  project_name         = var.project_name
  environment          = var.environment
  region               = var.region
  ssh_key_name         = var.ssh_key_name
  vpc_uuid             = data.digitalocean_vpc.default.id
  web_tag_name         = digitalocean_tag.roles["web"].name
  game_tag_name        = digitalocean_tag.roles["game"].name
  db_tag_name          = digitalocean_tag.roles["db"].name
  db_private_ip        = module.database.db_droplet_private_ip
  
  enable_game_server   = var.enable_game_server
  enable_load_balancer = var.enable_load_balancer
  
  web_droplet_count    = var.web_droplet_count
  web_droplet_size    = var.web_droplet_size
  game_droplet_size   = var.game_droplet_size
  web_droplet_image   = local.web_image
  game_droplet_image = local.game_image
  game_volume_size    = var.game_volume_size
  
  mu_db_port          = var.mu_db_port
  mu_db_name          = var.mu_db_name
  mu_db_user          = var.mu_db_user
  mu_db_password      = var.mu_db_password
  mu_website_port     = var.mu_website_port
  docker_hub_username = var.docker_hub_username
}

# -----------------------------------------------------------------------------
# Module: Networking (Load Balancer, Firewalls, DNS)
# -----------------------------------------------------------------------------
module "networking" {
  source = "../../modules/networking"

  project_name         = var.project_name
  environment          = var.environment
  region               = var.region
  domain_name          = var.domain_name
  ssh_allowed_ips     = var.ssh_allowed_ips
  ssh_key_name         = var.ssh_key_name

  enable_load_balancer = var.enable_load_balancer
  enable_game_server  = var.enable_game_server

  mu_website_port     = var.mu_website_port
  mu_db_port          = var.mu_db_port

  web_tag_name        = digitalocean_tag.roles["web"].name
  db_tag_name         = digitalocean_tag.roles["db"].name
  game_tag_name       = digitalocean_tag.roles["game"].name

  web_droplet_ips     = module.compute.web_droplet_ips
  db_droplet_ip       = module.database.db_droplet_ip
  game_droplet_ips    = module.compute.game_droplet_ips
}