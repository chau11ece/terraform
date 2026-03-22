# Data sources for Packer-built custom snapshots
#
# After building snapshots with Packer, copy this file to ../snapshots.tf
# Then update your droplet resources to use these instead of vanilla Ubuntu
#
# Usage:
#   resource "digitalocean_droplet" "web" {
#     image = data.digitalocean_image.mu_web_base.id  # ← Use this instead of var.web_droplet_image
#     ...
#   }

# Web server snapshot (Docker + pre-pulled web image)
data "digitalocean_image" "mu_web_base" {
  name = "mu-web-base-*"  # Matches mu-web-base-YYYYMMDD from Packer

  # If multiple snapshots exist, get the newest one
  # (Useful when you rebuild snapshots periodically)
}

# Database server snapshot (Docker + pre-pulled MSSQL image)
data "digitalocean_image" "mu_db_base" {
  name = "mu-db-base-*"
}

# Game server snapshot (Wine + ODBC + FreeTDS pre-configured)
data "digitalocean_image" "mu_game_base" {
  name = "mu-game-base-*"
}

# OPTIONAL: Outputs to verify snapshot IDs
output "custom_snapshot_ids" {
  description = "IDs of custom Packer-built snapshots"
  value = {
    web  = data.digitalocean_image.mu_web_base.id
    db   = data.digitalocean_image.mu_db_base.id
    game = data.digitalocean_image.mu_game_base.id
  }
}

output "custom_snapshot_info" {
  description = "Detailed info about custom snapshots"
  value = {
    web = {
      id      = data.digitalocean_image.mu_web_base.id
      name    = data.digitalocean_image.mu_web_base.name
      created = data.digitalocean_image.mu_web_base.created_at
      size_gb = data.digitalocean_image.mu_web_base.size_gigabytes
    }
    db = {
      id      = data.digitalocean_image.mu_db_base.id
      name    = data.digitalocean_image.mu_db_base.name
      created = data.digitalocean_image.mu_db_base.created_at
      size_gb = data.digitalocean_image.mu_db_base.size_gigabytes
    }
    game = {
      id      = data.digitalocean_image.mu_game_base.id
      name    = data.digitalocean_image.mu_game_base.name
      created = data.digitalocean_image.mu_game_base.created_at
      size_gb = data.digitalocean_image.mu_game_base.size_gigabytes
    }
  }
}
