# =============================================================================
# Database Module - Variables
# Handles DB droplet and volumes
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

variable "db_tag_name" {
  description = "Tag name for database droplets"
  type        = string
}

# -----------------------------------------------------------------------------
# Droplet Configuration
# -----------------------------------------------------------------------------
variable "db_droplet_size" {
  description = "Database droplet size"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "db_volume_size" {
  description = "Database volume size in GB"
  type        = number
  default     = 10
}

variable "web_droplet_image" {
  description = "OS image for droplets"
  type        = string
  default     = "ubuntu-22-04-x64"
}

# -----------------------------------------------------------------------------
# Database Configuration (for user_data)
# -----------------------------------------------------------------------------
variable "mu_db_password" {
  description = "MSSQL password"
  type        = string
  sensitive   = true
}

variable "enable_provisioners" {
  description = "Run provisioners?"
  type        = bool
  default     = false
}
