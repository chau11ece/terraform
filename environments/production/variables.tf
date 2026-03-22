# =============================================================================
# Dev Environment - Variables
# =============================================================================

# -----------------------------------------------------------------------------
# DigitalOcean Authentication
# -----------------------------------------------------------------------------
variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Project Identity
# -----------------------------------------------------------------------------
variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "mu-online"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

# -----------------------------------------------------------------------------
# Region & Sizing
# -----------------------------------------------------------------------------
variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "sgp1"
}

variable "web_droplet_count" {
  description = "Number of web droplets"
  type        = number
  default     = 1
}

variable "web_droplet_size" {
  description = "Web droplet size"
  type        = string
  default     = "s-1vcpu-1gb"
}

variable "db_droplet_size" {
  description = "Database droplet size"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "game_droplet_size" {
  description = "Game droplet size"
  type        = string
  default     = "s-4vcpu-8gb"
}

variable "db_volume_size" {
  description = "Database volume size in GB"
  type        = number
  default     = 10
}

variable "game_volume_size" {
  description = "Game volume size in GB"
  type        = number
  default     = 10
}

variable "web_droplet_image" {
  description = "OS image for droplets"
  type        = string
  default     = "ubuntu-22-04-x64"
}

# -----------------------------------------------------------------------------
# Feature Toggles
# -----------------------------------------------------------------------------
variable "enable_load_balancer" {
  description = "Create a load balancer?"
  type        = bool
  default     = false  # Dev: no LB to save $12/mo
}

variable "enable_game_server" {
  description = "Create game server?"
  type        = bool
  default     = false  # Dev: no game server to save $48/mo
}

variable "enable_provisioners" {
  description = "Run provisioners?"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Networking & DNS
# -----------------------------------------------------------------------------
variable "domain_name" {
  description = "Your domain name"
  type        = string
}

variable "ssh_key_name" {
  description = "Name of SSH key in DigitalOcean"
  type        = string
  default     = "mu-deploy-key"
}

variable "ssh_allowed_ips" {
  description = "List of CIDR blocks allowed to SSH"
  type        = list(string)
}

# -----------------------------------------------------------------------------
# Database Configuration
# -----------------------------------------------------------------------------
variable "mu_db_port" {
  description = "MSSQL port"
  type        = number
  default     = 1433
}

variable "mu_db_name" {
  description = "MSSQL database name"
  type        = string
  default     = "MuOnline"
}

variable "mu_db_user" {
  description = "MSSQL username"
  type        = string
}

variable "mu_db_password" {
  description = "MSSQL password"
  type        = string
  sensitive   = true
}

variable "mu_website_port" {
  description = "Website container port"
  type        = number
  default     = 8080
}

variable "docker_hub_username" {
  description = "Docker Hub username"
  type        = string
}
