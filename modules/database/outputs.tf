# =============================================================================
# Database Module - Outputs
# =============================================================================

output "db_droplet_ip" {
  description = "Database droplet public IP"
  value       = digitalocean_droplet.db.ipv4_address
}

output "db_droplet_private_ip" {
  description = "Database droplet private IP"
  value       = digitalocean_droplet.db.ipv4_address_private
}

output "db_droplet_id" {
  description = "Database droplet ID"
  value       = digitalocean_droplet.db.id
}

output "ssh_command_db" {
  description = "SSH command to database droplet"
  value       = "ssh root@${digitalocean_droplet.db.ipv4_address}"
}

output "db_volume_id" {
  description = "Database volume ID"
  value       = digitalocean_volume.mssql_data.id
}

output "db_volume_name" {
  description = "Database volume name"
  value       = digitalocean_volume.mssql_data.name
}
