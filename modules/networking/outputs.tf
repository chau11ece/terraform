# =============================================================================
# Networking Module - Outputs
# =============================================================================

output "load_balancer_ip" {
  description = "Load balancer public IP"
  value       = var.enable_load_balancer ? digitalocean_loadbalancer.web_lb[0].ip : "disabled"
}

output "load_balancer_id" {
  description = "Load balancer ID"
  value       = var.enable_load_balancer ? digitalocean_loadbalancer.web_lb[0].id : ""
}

output "domain_id" {
  description = "Domain ID for DNS"
  value       = digitalocean_domain.mu_domain.id
}

output "domain_name" {
  description = "Domain name"
  value       = digitalocean_domain.mu_domain.name
}

output "website_url" {
  description = "Website URL"
  value       = "http://${var.domain_name}"
}

output "web_tag_name" {
  description = "Tag name for web droplets"
  value       = digitalocean_tag.roles["web"].name
}

output "db_tag_name" {
  description = "Tag name for database droplets"
  value       = digitalocean_tag.roles["db"].name
}

output "game_tag_name" {
  description = "Tag name for game droplets"
  value       = digitalocean_tag.roles["game"].name
}

output "vpc_id" {
  description = "VPC ID"
  value       = data.digitalocean_vpc.default.id
}

output "vpc_ip_range" {
  description = "VPC IP range"
  value       = data.digitalocean_vpc.default.ip_range
}
