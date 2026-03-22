# =============================================================================
# Networking Module - Variables
# Handles VPC, Firewalls, DNS, and Load Balancer
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

variable "domain_name" {
  description = "Your domain name"
  type        = string
}

variable "ssh_allowed_ips" {
  description = "List of CIDR blocks allowed to SSH"
  type        = list(string)
}

variable "ssh_key_name" {
  description = "Name of SSH key in DigitalOcean"
  type        = string
}

# -----------------------------------------------------------------------------
# Feature Toggles
# -----------------------------------------------------------------------------
variable "enable_load_balancer" {
  description = "Create a load balancer?"
  type        = bool
  default     = true
}

variable "enable_game_server" {
  description = "Create game server resources?"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Networking Configuration
# -----------------------------------------------------------------------------
variable "mu_website_port" {
  description = "Port your MU website container listens on"
  type        = number
  default     = 8080
}

variable "mu_db_port" {
  description = "MSSQL port"
  type        = number
  default     = 1433
}

# -----------------------------------------------------------------------------
# Droplet Tags (passed from compute module)
# -----------------------------------------------------------------------------
variable "web_tag_name" {
  description = "Tag name for web droplets"
  type        = string
}

variable "db_tag_name" {
  description = "Tag name for database droplets"
  type        = string
}

variable "game_tag_name" {
  description = "Tag name for game droplets"
  type        = string
}

# -----------------------------------------------------------------------------
# Load Balancer ID (passed when LB exists)
# -----------------------------------------------------------------------------
variable "load_balancer_id" {
  description = "ID of the load balancer (if enabled)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Droplet IPs (for DNS records)
# -----------------------------------------------------------------------------
variable "web_droplet_ips" {
  description = "List of web droplet public IPs"
  type        = list(string)
  default     = []
}

variable "db_droplet_ip" {
  description = "Database droplet public IP"
  type        = string
  default     = ""
}

variable "game_droplet_ips" {
  description = "List of game droplet public IPs"
  type        = list(string)
  default     = []
}

variable "web_droplet_private_ips" {
  description = "List of web droplet private IPs"
  type        = list(string)
  default     = []
}
