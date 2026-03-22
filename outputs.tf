# =============================================================================
# MU Online Infrastructure - Outputs
# These values are printed after `terraform apply` — save them!
# =============================================================================

# [*] = "splat" expression — collects the value from ALL counted resources
output "web_droplet_ips" {
  description = "Public IPs of all MU website droplets"
  value       = digitalocean_droplet.web[*].ipv4_address
}

# Conditional output: only show LB IP when it exists
# try() returns fallback "none" if the LB doesn't exist
output "load_balancer_ip" {
  description = "Load balancer public IP (only in production)"
  value       = var.enable_load_balancer ? digitalocean_loadbalancer.web_lb[0].ip : "disabled"
}

output "website_url" {
  description = "Your MU website URL"
  value       = "http://${var.domain_name}"
}

output "ssh_command" {
  description = "SSH command to connect to your first web droplet"
  value       = "ssh root@${digitalocean_droplet.web[0].ipv4_address}"
}

output "ssh_commands_all_web" {
  description = "SSH commands for all web droplets"
  value       = [for ip in digitalocean_droplet.web[*].ipv4_address : "ssh root@${ip}"]
}

output "db_droplet_ip" {
  description = "Public IP of your DB droplet — use this for SSH"
  value       = digitalocean_droplet.db.ipv4_address
}

output "db_droplet_private_ip" {
  description = "Private IP of your DB droplet — web droplet connects here"
  value       = digitalocean_droplet.db.ipv4_address_private
}

output "db_ssh_command" {
  description = "SSH command to connect to your DB droplet"
  value       = "ssh root@${digitalocean_droplet.db.ipv4_address}"
}

output "db_connection_note" {
  description = "How the web droplet reaches MSSQL"
  value       = "MU website connects to MSSQL at ${digitalocean_droplet.db.ipv4_address_private}:${var.mu_db_port} (private network)"
}

output "web_droplet_ids" {
  description = "Droplet IDs for all web droplets"
  value       = digitalocean_droplet.web[*].id
}

# -----------------------------------------------------------------------------
# Game Droplet Outputs  (conditional — only shown when game server is enabled)
# -----------------------------------------------------------------------------
output "game_droplet_ip" {
  description = "Public IP of game droplet — clients connect here"
  value       = var.enable_game_server ? digitalocean_droplet.game[0].ipv4_address : "disabled"
}

output "game_droplet_private_ip" {
  description = "Private IP of game droplet — for internal network"
  value       = var.enable_game_server ? digitalocean_droplet.game[0].ipv4_address_private : "disabled"
}

output "game_ssh_command" {
  description = "SSH command to connect to your game droplet"
  value       = var.enable_game_server ? "ssh root@${digitalocean_droplet.game[0].ipv4_address}" : "game server disabled"
}

output "game_sync_command" {
  description = "rsync command to upload game server files"
  value       = var.enable_game_server ? "rsync -avz --progress /path/to/mu-online-server/ root@${digitalocean_droplet.game[0].ipv4_address}:/opt/mu-online/ --exclude='.git' --exclude='DB/' --exclude='*.md'" : "game server disabled"
}

# -----------------------------------------------------------------------------
# Data Source Outputs  (info from existing DO resources)
# -----------------------------------------------------------------------------
output "vpc_info" {
  description = "VPC that all droplets share (enables private networking)"
  value       = "${data.digitalocean_vpc.default.name} (${data.digitalocean_vpc.default.ip_range})"
}

output "account_droplet_limit" {
  description = "Your DO account droplet limit — request increase if you hit it"
  value       = "Using ${data.digitalocean_account.current.droplet_limit} droplet limit"
}

output "latest_ubuntu_image" {
  description = "Latest Ubuntu image available on DO"
  value       = length(data.digitalocean_images.ubuntu.images) > 0 ? data.digitalocean_images.ubuntu.images[0].slug : "none found"
}
