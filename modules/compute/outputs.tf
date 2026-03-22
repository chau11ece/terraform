# =============================================================================
# Compute Module - Outputs
# =============================================================================

output "web_droplet_ips" {
  description = "Public IPs of all web droplets"
  value       = digitalocean_droplet.web[*].ipv4_address
}

output "web_droplet_private_ips" {
  description = "Private IPs of all web droplets"
  value       = digitalocean_droplet.web[*].ipv4_address_private
}

output "web_droplet_ids" {
  description = "IDs of all web droplets"
  value       = digitalocean_droplet.web[*].id
}

output "ssh_command_web" {
  description = "SSH command to first web droplet"
  value       = length(digitalocean_droplet.web) > 0 ? "ssh root@${digitalocean_droplet.web[0].ipv4_address}" : ""
}

output "ssh_commands_web" {
  description = "SSH commands for all web droplets"
  value       = [for ip in digitalocean_droplet.web[*].ipv4_address : "ssh root@${ip}"]
}

output "game_droplet_ips" {
  description = "Public IPs of game droplets"
  value       = var.enable_game_server ? digitalocean_droplet.game[*].ipv4_address : []
}

output "game_droplet_private_ips" {
  description = "Private IPs of game droplets"
  value       = var.enable_game_server ? digitalocean_droplet.game[*].ipv4_address_private : []
}

output "game_droplet_id" {
  description = "ID of first game droplet"
  value       = var.enable_game_server ? digitalocean_droplet.game[0].id : ""
}

output "ssh_command_game" {
  description = "SSH command to game droplet"
  value       = var.enable_game_server ? "ssh root@${digitalocean_droplet.game[0].ipv4_address}" : "disabled"
}

output "game_volume_id" {
  description = "Game data volume ID"
  value       = digitalocean_volume.game_data.id
}

output "game_volume_name" {
  description = "Game data volume name"
  value       = digitalocean_volume.game_data.name
}
