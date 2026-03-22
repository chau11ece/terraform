# =============================================================================
# Networking Module - Main
# Handles VPC lookup, Firewalls, DNS, and Load Balancer
# =============================================================================

terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.34"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "digitalocean_vpc" "default" {
  region = var.region
}

data "digitalocean_ssh_key" "deploy_key" {
  name = var.ssh_key_name
}

# -----------------------------------------------------------------------------
# Tags (referenced by firewalls)
# -----------------------------------------------------------------------------
resource "digitalocean_tag" "roles" {
  for_each = toset(["web", "db", "game"])
  name     = each.value
}

# -----------------------------------------------------------------------------
# Load Balancer
# -----------------------------------------------------------------------------
resource "digitalocean_loadbalancer" "web_lb" {
  count = var.enable_load_balancer ? 1 : 0

  name   = "${var.project_name}-lb-${var.environment}"
  region = var.region

  forwarding_rule {
    entry_port      = 80
    entry_protocol  = "http"
    target_port     = var.mu_website_port
    target_protocol = "http"
  }

  healthcheck {
    port                     = var.mu_website_port
    protocol                 = "http"
    path                     = "/health.php"
    check_interval_seconds   = 10
    response_timeout_seconds = 5
    unhealthy_threshold      = 3
    healthy_threshold        = 2
  }

  droplet_tag = var.web_tag_name
}

# -----------------------------------------------------------------------------
# Web Firewall
# -----------------------------------------------------------------------------
resource "digitalocean_firewall" "web_firewall" {
  name = "${var.project_name}-web-firewall-${var.environment}"

  tags = [var.web_tag_name]

  # Dynamic inbound rule based on LB presence
  dynamic "inbound_rule" {
    for_each = var.enable_load_balancer ? [1] : []
    content {
      protocol                  = "tcp"
      port_range                = tostring(var.mu_website_port)
      source_load_balancer_uids = [digitalocean_loadbalancer.web_lb[0].id]
    }
  }

  dynamic "inbound_rule" {
    for_each = var.enable_load_balancer ? [] : [1]
    content {
      protocol         = "tcp"
      port_range       = tostring(var.mu_website_port)
      source_addresses = ["0.0.0.0/0", "::/0"]
    }
  }

  # SSH
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_allowed_ips
  }

  # ICMP
  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Outbound rules
  outbound_rule {
    protocol              = "tcp"
    port_range            = "443"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "80"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "53"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow MSSQL out to DB
  outbound_rule {
    protocol         = "tcp"
    port_range       = tostring(var.mu_db_port)
    destination_tags = [var.db_tag_name]
  }
}

# -----------------------------------------------------------------------------
# Game Firewall
# -----------------------------------------------------------------------------
resource "digitalocean_firewall" "game_firewall" {
  count = var.enable_game_server ? 1 : 0

  name = "${var.project_name}-game-firewall-${var.environment}"

  tags = [var.game_tag_name]

  # ConnectServer port
  inbound_rule {
    protocol         = "tcp"
    port_range       = "44405"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Game server ports
  inbound_rule {
    protocol         = "tcp"
    port_range       = "55901-55941"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # MHPServer (anti-hack)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "55999"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # SSH
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_allowed_ips
  }

  # ICMP
  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Outbound rules
  outbound_rule {
    protocol              = "tcp"
    port_range            = "443"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "80"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "53"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow MSSQL out
  outbound_rule {
    protocol         = "tcp"
    port_range       = "1433"
    destination_tags = [var.db_tag_name]
  }
}

# -----------------------------------------------------------------------------
# Database Firewall
# -----------------------------------------------------------------------------
resource "digitalocean_firewall" "db_firewall" {
  name = "${var.project_name}-db-firewall-${var.environment}"

  tags = [var.db_tag_name]

  # Allow MSSQL from web and game
  inbound_rule {
    protocol   = "tcp"
    port_range = "1433"
    source_tags = var.enable_game_server ? [
      var.web_tag_name,
      var.game_tag_name
    ] : [
      var.web_tag_name
    ]
  }

  # SSH
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_allowed_ips
  }

  # ICMP
  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Outbound
  outbound_rule {
    protocol              = "tcp"
    port_range            = "443"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "80"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "53"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# -----------------------------------------------------------------------------
# DNS Domain
# -----------------------------------------------------------------------------
resource "digitalocean_domain" "mu_domain" {
  name = var.domain_name
}

# -----------------------------------------------------------------------------
# DNS Records
# -----------------------------------------------------------------------------
# Root domain -> LB or first web droplet
resource "digitalocean_record" "root" {
  domain = digitalocean_domain.mu_domain.id
  type   = "A"
  name   = "@"
  value  = length(var.web_droplet_ips) > 0 ? var.web_droplet_ips[0] : ""
  ttl    = 300
}

# www -> same as root
resource "digitalocean_record" "www" {
  domain = digitalocean_domain.mu_domain.id
  type   = "A"
  name   = "www"
  value  = length(var.web_droplet_ips) > 0 ? var.web_droplet_ips[0] : ""
  ttl    = 300
}

# Direct web droplet access (web0, web1, etc.)
resource "digitalocean_record" "web_direct" {
  count = length(var.web_droplet_ips)

  domain = digitalocean_domain.mu_domain.id
  type   = "A"
  name   = "web${count.index}"
  value  = var.web_droplet_ips[count.index]
  ttl    = 300
}

# DB and Game DNS records
resource "digitalocean_record" "direct" {
  for_each = merge(
    var.db_droplet_ip != "" ? { db = var.db_droplet_ip } : {},
    var.enable_game_server && length(var.game_droplet_ips) > 0 ? 
      { for i, ip in var.game_droplet_ips : "game${i}" => ip } : {}
  )

  domain = digitalocean_domain.mu_domain.id
  type   = "A"
  name   = each.key
  value  = each.value
  ttl    = 300
}
