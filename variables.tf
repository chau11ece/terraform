# =============================================================================
# MU Online Infrastructure - Variables
# Wednesday: Infrastructure as Code with Terraform
# =============================================================================

# -----------------------------------------------------------------------------
# DigitalOcean Authentication
# -----------------------------------------------------------------------------
variable "do_token" {
  description = "DigitalOcean API token - set via TF_VAR_do_token env variable, never hardcode!"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Project Identity
# -----------------------------------------------------------------------------
variable "project_name" {
  description = "Name prefix for all resources — keeps things organized in DO console"
  type        = string
  default     = "mu-online"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "dev"], var.environment)
    error_message = "Environment must be: production, staging, or dev."
  }
}

# -----------------------------------------------------------------------------
# Region & Sizing
# -----------------------------------------------------------------------------
variable "region" {
  description = "DigitalOcean region. sgp1=Singapore (closest to VN), sin1=Singapore alt"
  type        = string
  default     = "sgp1" # Best latency from Vietnam

  validation {
    condition     = contains(["sgp1", "sin1", "nyc3", "lon1", "fra1"], var.region)
    error_message = "Choose a valid DO region."
  }
}

variable "web_droplet_count" {
  description = "Number of web droplets behind the load balancer (count demo!)"
  type        = number
  default     = 1 # Start with 1, scale up to 2 or 3 when needed

  validation {
    condition     = var.web_droplet_count >= 1 && var.web_droplet_count <= 5
    error_message = "Web droplet count must be between 1 and 5."
  }
}

# -----------------------------------------------------------------------------
# Feature Toggles  (conditional resources demo!)
# -----------------------------------------------------------------------------
variable "enable_load_balancer" {
  description = "Create a load balancer? true for production, false for dev (saves $12/month)"
  type        = bool
  default     = true
}

variable "enable_game_server" {
  description = "Create game droplet? false = web+db only (saves $48/month for testing)"
  type        = bool
  default     = true
}

variable "enable_provisioners" {
  description = "Run provisioners (wait for services + auto-restore DB)? false = fast deploy, true = verified deploy"
  type        = bool
  default     = false # Fast by default — use true when you need guaranteed ready state
}

variable "web_droplet_size" {
  description = "Droplet size for MU website. s-1vcpu-1gb is fine for website-only"
  type        = string
  default     = "s-1vcpu-1gb" # $6/month — enough for containerized website
}

variable "db_droplet_size" {
  description = "Droplet size for MSSQL database. s-2vcpu-4gb needed for SQL Server"
  type        = string
  default     = "s-2vcpu-4gb" # $24/month — MSSQL needs at least 2GB RAM
}

variable "game_droplet_size" {
  description = "Droplet size for game servers. s-4vcpu-8gb runs all servers comfortably"
  type        = string
  default     = "s-4vcpu-8gb" # $48/month — 8GB RAM for Wine + all game servers
}

variable "db_volume_size" {
  description = "Size in GB for the persistent MSSQL data volume ($0.10/GB/month)"
  type        = number
  default     = 10 # $1/month — enough for MU Online database
}

variable "game_volume_size" {
  description = "Size in GB for persistent game server files volume ($0.10/GB/month)"
  type        = number
  default     = 10 # $1/month — enough for all game server files
}

variable "web_droplet_image" {
  description = "OS image. Ubuntu 22.04 LTS is stable and well-documented"
  type        = string
  default     = "ubuntu-22-04-x64"
}

# -----------------------------------------------------------------------------
# Networking & DNS
# -----------------------------------------------------------------------------
variable "domain_name" {
  description = "Your domain name e.g. muonline.yourdomain.com"
  type        = string
  # No default — you MUST provide this in terraform.tfvars
}

# -----------------------------------------------------------------------------
# SSH Access
# -----------------------------------------------------------------------------
variable "ssh_key_name" {
  description = "Name of your SSH key already uploaded to DigitalOcean"
  type        = string
  default     = "mu-deploy-key"
}

variable "ssh_allowed_ips" {
  description = "List of CIDR blocks allowed to SSH into the droplet. Lock this to your IPs!"
  type        = list(string)
  # Default includes your VPS IP. Add your home/office IP too.
  # Example: ["1.54.153.162/32", "YOUR.HOME.IP/32"]
}

# -----------------------------------------------------------------------------
# MU Website Config (passed as droplet user_data / env vars)
# -----------------------------------------------------------------------------
variable "mu_db_host" {
  description = "MSSQL host — auto-set to DB droplet private IP when empty"
  type        = string
  default     = "" # Leave empty: Terraform uses the DB droplet's private IP
  sensitive   = true
}

variable "mu_db_port" {
  description = "MSSQL port — 1433 is standard (private network, no ISP issues)"
  type        = number
  default     = 1433
}

variable "mu_db_name" {
  description = "MSSQL database name for MU website (e.g. MuOnline, GameDB)"
  type        = string
  default     = "MuOnline"
}

variable "mu_db_user" {
  description = "MSSQL username for website connection"
  type        = string
  sensitive   = true
}

variable "mu_db_password" {
  description = "MSSQL password — use TF_VAR_mu_db_password, never hardcode!"
  type        = string
  sensitive   = true
}

variable "mu_website_port" {
  description = "Port your MU website Docker container listens on"
  type        = number
  default     = 8080 # Docker maps 8080:80 in docker-compose.yml
}

# -----------------------------------------------------------------------------
# Docker Hub
# -----------------------------------------------------------------------------
variable "docker_hub_username" {
  description = "Your Docker Hub username (used to pull the mu-web image)"
  type        = string
}
