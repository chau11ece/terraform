# =============================================================================
# Dev Environment - Outputs
# =============================================================================

output "website_url" {
  description = "Website URL"
  value       = module.networking.website_url
}

output "load_balancer_ip" {
  description = "Load balancer IP"
  value       = module.networking.load_balancer_ip
}

output "web_droplet_ips" {
  description = "Web droplet IPs"
  value       = module.compute.web_droplet_ips
}

output "db_droplet_ip" {
  description = "Database droplet IP"
  value       = module.database.db_droplet_ip
}

output "db_droplet_private_ip" {
  description = "Database droplet private IP"
  value       = module.database.db_droplet_private_ip
}

output "game_droplet_ips" {
  description = "Game droplet IPs"
  value       = module.compute.game_droplet_ips
}

output "ssh_command_web" {
  description = "SSH command to web droplet"
  value       = module.compute.ssh_command_web
}

output "ssh_command_db" {
  description = "SSH command to database droplet"
  value       = module.database.ssh_command_db
}

output "ssh_command_game" {
  description = "SSH command to game droplet"
  value       = module.compute.ssh_command_game
}

output "vpc_info" {
  description = "VPC info"
  value       = "${data.digitalocean_vpc.default.name} (${data.digitalocean_vpc.default.ip_range})"
}

output "account_droplet_limit" {
  description = "Account droplet limit"
  value       = "Using ${data.digitalocean_account.current.droplet_limit} droplet limit"
}

output "latest_ubuntu_image" {
  description = "Latest Ubuntu image"
  value       = length(data.digitalocean_images.ubuntu.images) > 0 ? data.digitalocean_images.ubuntu.images[0].slug : "none found"
}
