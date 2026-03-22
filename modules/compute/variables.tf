# =============================================================================
# Compute Module - Variables
# Handles Web and Game droplets
# =============================================================================

# -----------------------------------------------------------------------------
# Required Inputs
# -----------------------------------------------------------------------------
variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
}

variable "ssh_key_name" {
  description = "Name of SSH key in DigitalOcean"
  type        = string
}

variable "vpc_uuid" {
  description = "VPC UUID for droplets"
  type        = string
}

# -----------------------------------------------------------------------------
# Tags (from networking module)
# -----------------------------------------------------------------------------
variable "web_tag_name" {
  description = "Tag name for web droplets"
  type        = string
}

variable "game_tag_name" {
  description = "Tag name for game droplets"
  type        = string
}

variable "db_tag_name" {
  description = "Tag name for database droplets"
  type        = string
}

variable "db_private_ip" {
  description = "Database droplet private IP"
  type        = string
}

# -----------------------------------------------------------------------------
# Feature Toggles
# -----------------------------------------------------------------------------
variable "enable_game_server" {
  description = "Create game server resources?"
  type        = bool
  default     = true
}

variable "enable_load_balancer" {
  description = "Create a load balancer?"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Droplet Configuration
# -----------------------------------------------------------------------------
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

variable "game_droplet_size" {
  description = "Game droplet size"
  type        = string
  default     = "s-4vcpu-8gb"
}

variable "web_droplet_image" {
  description = "OS image for web droplets"
  type        = string
  default     = "ubuntu-22-04-x64"
}

variable "game_droplet_image" {
  description = "OS image for game droplets (can be Packer snapshot)"
  type        = string
  default     = "ubuntu-22-04-x64"
}

variable "game_volume_size" {
  description = "Game volume size in GB"
  type        = number
  default     = 10
}

# -----------------------------------------------------------------------------
# Database Configuration (for user_data)
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
