# =============================================================================
# MU Online Infrastructure - Main Entry Point
# Wednesday: Infrastructure as Code with Terraform
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.34"
    }
  }

  # -------------------------------------------------------------------------
  # STATE BACKEND (from Tuesday's lesson!)
  # Uncomment this block after you've run `terraform init` once locally.
  # Stores your state file in DigitalOcean Spaces (S3-compatible).
  # -------------------------------------------------------------------------
  # backend "s3" {
  #   endpoint                    = "https://sgp1.digitaloceanspaces.com"
  #   bucket                      = "mu-terraform-state"
  #   key                         = "production/terraform.tfstate"
  #   region                      = "us-east-1"   # required by S3 protocol, value doesn't matter
  #   skip_credentials_validation = true
  #   skip_metadata_api_check     = true
  #   skip_region_validation      = true
  #   force_path_style            = true
  #   # Set via env: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (use DO Spaces keys)
  # }
}

# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------
provider "digitalocean" {
  token = var.do_token
}

# -----------------------------------------------------------------------------
# DigitalOcean Project  (groups all resources in DO console — very handy)
# Commented out - causes issues when recreating
# -----------------------------------------------------------------------------
# resource "digitalocean_project" "mu_project" {
#   name        = var.project_name
#   description = "MU Online game infrastructure — web server, load balancer, DNS"
#   purpose     = "Web Application"
#   environment = title(var.environment) # DO expects "Production", "Staging", etc.
# }

# Attach all resources to this project
# resource "digitalocean_project_resources" "mu_resources" {
#   project = digitalocean_project.mu_project.id

#   resources = [
#     digitalocean_droplet.web.urn,
#     digitalocean_loadbalancer.web_lb.urn,
#     digitalocean_domain.mu_domain.urn,
#   ]
# }

# =============================================================================
# DATA SOURCES — read existing resources, don't create them
# =============================================================================

# 1. SSH Key (you already had this one!)
#    Looks up a key that was manually created in DO console
#    Used by: all droplets → ssh_keys = [data.digitalocean_ssh_key.deploy_key.id]
data "digitalocean_ssh_key" "deploy_key" {
  name = var.ssh_key_name
}

# 2. VPC — explicitly managed instead of relying on DO's implicit per-region
#    default. DO removes that implicit VPC once a region has zero resources
#    left in it, which breaks the old `data "digitalocean_vpc"` lookup on any
#    from-scratch rebuild (hit this exact failure recreating sgp1 resources).
resource "digitalocean_vpc" "default" {
  name     = "default-${var.region}"
  region   = var.region
  # DO auto-provisioned this the instant the first sgp1 resource (a volume/LB)
  # was created mid-apply, before this resource block ran — imported below
  # rather than created, so the ip_range must match what DO actually assigned.
  ip_range = "10.104.0.0/20"
}

# 3. Account info — check your droplet limit before trying to create
#    Useful for: validation, outputs, debugging "droplet limit exceeded" errors
data "digitalocean_account" "current" {}

# 4. Latest Ubuntu image — always get the newest LTS, no hardcoded string
#    Before: image = "ubuntu-22-04-x64"  (hardcoded, gets stale)
#    After:  image = data.digitalocean_images.ubuntu.images[0].slug  (always latest)
data "digitalocean_images" "ubuntu" {
  filter {
    key    = "distribution"
    values = ["Ubuntu"]
  }
  filter {
    key    = "status"
    values = ["available"]
  }
  # distribution=Ubuntu + type=base still isn't enough to isolate the
  # standard server image — DO's GPU-droplet base images (slug gpu-*-base)
  # are also distribution=Ubuntu, type=base, and get created/refreshed more
  # recently, so they sort ahead of the real ubuntu-24-04-x64 base image.
  # Pin the slug directly instead of trusting "sort by newest" here.
  filter {
    key    = "slug"
    values = ["ubuntu-24-04-x64"]
  }
}

# -----------------------------------------------------------------------------
# Tags  (must exist BEFORE firewalls reference them)
# -----------------------------------------------------------------------------
# for_each with toset() — creates one tag per item in the set
# Referenced as: digitalocean_tag.roles["web"].name, digitalocean_tag.roles["db"].name, etc.
# To add a new role: just add it to the set — e.g., "monitor", "cache"
resource "digitalocean_tag" "roles" {
  for_each = toset(["web", "db", "game"])
  name     = each.value  # each.value = "web", "db", or "game"
}

# -----------------------------------------------------------------------------
# Module: Web Droplet  (your MU website Docker host)
# -----------------------------------------------------------------------------
# count = var.web_droplet_count → creates N identical web droplets
# Each one gets a unique index: count.index = 0, 1, 2, ...
resource "digitalocean_droplet" "web" {
  count = var.web_droplet_count

  # Each droplet gets a unique name: mu-online-web-production-0, -1, -2...
  name     = "${var.project_name}-web-${var.environment}-${count.index}"
  image    = var.web_droplet_image
  size     = var.web_droplet_size
  region   = var.region
  vpc_uuid = digitalocean_vpc.default.id
  ssh_keys = [data.digitalocean_ssh_key.deploy_key.id]

  # Cloud-init script — runs once on first boot
  # Installs Docker and starts your MU website container
  user_data = templatefile("${path.module}/scripts/web-init.sh", {
    mu_db_host      = digitalocean_droplet.db.ipv4_address_private,
    mu_db_port      = var.mu_db_port,
    mu_db_name      = var.mu_db_name,
    mu_db_user      = var.mu_db_user,
    mu_db_password  = var.mu_db_password,
    mu_website_port = var.mu_website_port,
    environment     = var.environment,
    # For docker-compose environment variables
    public_ip           = digitalocean_droplet.db.ipv4_address_private,
    db_host             = digitalocean_droplet.db.ipv4_address_private,
    db_port             = var.mu_db_port,
    db_name             = var.mu_db_name,
    db_user             = var.mu_db_user,
    db_pass             = var.mu_db_password,
    docker_hub_username = var.docker_hub_username,
  })

  tags = [
    var.project_name,
    digitalocean_tag.roles["web"].name,
    var.environment
  ]

  lifecycle {
    prevent_destroy = false
    # ignore_changes = [user_data]  # Uncomment after first deploy
  }
}

# -----------------------------------------------------------------------------
# Module: Persistent Volume  (Game server files survive droplet destroy/recreate)
# -----------------------------------------------------------------------------
resource "digitalocean_volume" "game_data" {
  region                  = var.region
  name                    = "${var.project_name}-game-data"
  size                    = var.game_volume_size
  initial_filesystem_type = "ext4"
  description             = "Persistent game server files for MU Online"

  # PROTECT: prevent terraform destroy from deleting game server files!
  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Module: Game Droplet  (conditional — only created when enable_game_server = true)
# -----------------------------------------------------------------------------
# enable_game_server = false → skips game droplet entirely (saves $48/month)
# Useful when you only need web+db for website testing
resource "digitalocean_droplet" "game" {
  count = var.enable_game_server ? 1 : 0

  name       = "${var.project_name}-game-${var.environment}"
  image      = var.web_droplet_image
  size       = var.game_droplet_size
  region     = var.region
  vpc_uuid   = digitalocean_vpc.default.id
  ssh_keys   = [data.digitalocean_ssh_key.deploy_key.id]
  volume_ids = [digitalocean_volume.game_data.id]

  # Cloud-init: installs Wine, creates systemd services, helper scripts
  # Public IP is auto-detected at boot via DO metadata API (can't self-reference)
  user_data = templatefile("${path.module}/scripts/game-init.sh", {
    db_private_ip  = digitalocean_droplet.db.ipv4_address_private
    mu_db_password = var.mu_db_password
    volume_name    = digitalocean_volume.game_data.name
  })

  tags = [
    var.project_name,
    digitalocean_tag.roles["game"].name,
    var.environment
  ]

  lifecycle {
    prevent_destroy = false
  }
}

# -----------------------------------------------------------------------------
# Module: Load Balancer  (conditional — only created when enable_load_balancer = true)
# -----------------------------------------------------------------------------
# count = var.enable_load_balancer ? 1 : 0
#   true  → count = 1 → LB exists      (production)
#   false → count = 0 → LB skipped     (dev — saves $12/month)
resource "digitalocean_loadbalancer" "web_lb" {
  count = var.enable_load_balancer ? 1 : 0

  name   = "${var.project_name}-lb-${var.environment}-new"
  region = var.region

  # Forward HTTP → your website port, and HTTPS → your website port
  forwarding_rule {
    entry_port      = 80
    entry_protocol  = "http"
    target_port     = var.mu_website_port
    target_protocol = "http"
  }

  # Health check — LB will stop sending traffic if website is down
  healthcheck {
    port                     = var.mu_website_port
    protocol                 = "http"
    path                     = "/health.php" # Fixed: health.php is the actual endpoint
    check_interval_seconds   = 10
    response_timeout_seconds = 5
    unhealthy_threshold      = 3
    healthy_threshold        = 2
  }

  # Only send traffic to droplets with the "web" tag
  droplet_tag = digitalocean_tag.roles["web"].name

  # Redirect HTTP → HTTPS (uncomment once SSL cert is set up)
  # redirect_http_to_https = true
}

# -----------------------------------------------------------------------------
# Module: Firewall
# -----------------------------------------------------------------------------
resource "digitalocean_firewall" "web_firewall" {
  name = "${var.project_name}-firewall-${var.environment}-new"

  # Apply to all droplets tagged "web"
  tags = [digitalocean_tag.roles["web"].name]

  # ---- INBOUND RULES -------------------------------------------------------

  # When LB exists: allow HTTP from LB only (production — secure)
  # When no LB:     allow HTTP from anywhere (dev — direct access)
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
      port_range       = "80"  # No LB → container maps directly to port 80
      source_addresses = ["0.0.0.0/0", "::/0"]
    }
  }

  # Allow SSH — restricted to your IPs only
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_allowed_ips
  }

  # Allow ICMP (ping) — useful for debugging connectivity
  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # ---- OUTBOUND RULES ------------------------------------------------------

  # Allow HTTPS out (to pull Docker images, updates etc.)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "443"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow HTTP out
  outbound_rule {
    protocol              = "tcp"
    port_range            = "80"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow DNS out (so droplet can resolve domain names)
  outbound_rule {
    protocol              = "udp"
    port_range            = "53"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow MSSQL out — so web container can reach the DB droplet (private network)
  outbound_rule {
    protocol         = "tcp"
    port_range       = tostring(var.mu_db_port)
    destination_tags = [digitalocean_tag.roles["db"].name]
  }
}

# -----------------------------------------------------------------------------
# Module: Game Firewall  (conditional — only when game server exists)
# -----------------------------------------------------------------------------
resource "digitalocean_firewall" "game_firewall" {
  count = var.enable_game_server ? 1 : 0

  name = "${var.project_name}-game-firewall-${var.environment}"

  # Apply to all droplets tagged "game"
  tags = [digitalocean_tag.roles["game"].name]

  # ---- INBOUND RULES -------------------------------------------------------

  # Public: ConnectServer (TCP 44405) — client server list
  inbound_rule {
    protocol         = "tcp"
    port_range       = "44405"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Public: GameServers (TCP 55901-55941) — gameplay
  inbound_rule {
    protocol         = "tcp"
    port_range       = "55901-55941"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Public: MHPServer (TCP 55999) — anti-hack
  inbound_rule {
    protocol         = "tcp"
    port_range       = "55999"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow SSH — restricted to your IPs only
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_allowed_ips
  }

  # Allow ICMP (ping) — useful for debugging connectivity
  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # ---- OUTBOUND RULES ------------------------------------------------------

  # Allow HTTPS out (Wine downloads, updates)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "443"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow HTTP out (package installs)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "80"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow DNS out
  outbound_rule {
    protocol              = "udp"
    port_range            = "53"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow MSSQL out — game droplet → DB droplet (private network)
  outbound_rule {
    protocol         = "tcp"
    port_range       = "1433"
    destination_tags = [digitalocean_tag.roles["db"].name]
  }
}

# -----------------------------------------------------------------------------
# Module: Persistent Volume  (MSSQL data survives droplet destroy/recreate)
# -----------------------------------------------------------------------------
resource "digitalocean_volume" "mssql_data" {
  region                  = var.region
  name                    = "${var.project_name}-mssql-data"
  size                    = var.db_volume_size
  initial_filesystem_type = "ext4"
  description             = "Persistent MSSQL data for MU Online"

  # PROTECT: prevent terraform destroy from deleting your database!
  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Module: DB Droplet  (MSSQL Server 2022 in Docker)
# -----------------------------------------------------------------------------
resource "digitalocean_droplet" "db" {
  name       = "${var.project_name}-db-${var.environment}"
  image      = var.web_droplet_image
  size       = var.db_droplet_size
  region     = var.region
  vpc_uuid   = digitalocean_vpc.default.id
  ssh_keys   = [data.digitalocean_ssh_key.deploy_key.id]
  volume_ids = [digitalocean_volume.mssql_data.id]

  user_data = templatefile("${path.module}/scripts/db-init.sh", {
    mu_db_password = var.mu_db_password,
    volume_name    = digitalocean_volume.mssql_data.name,
  })

  tags = [
    var.project_name,
    digitalocean_tag.roles["db"].name,
    var.environment
  ]

  lifecycle {
    prevent_destroy = false
  }
}

# -----------------------------------------------------------------------------
# OPTIONAL: Provisioners (only when enable_provisioners = true)
# Waits for services to be ready + auto-restores DB if needed
# Without this: deploy is ~2 min (cloud-init runs in background)
# With this:    deploy is ~12 min (waits for everything to be verified)
# -----------------------------------------------------------------------------
resource "terraform_data" "db_ready" {
  count = var.enable_provisioners ? 1 : 0

  depends_on = [digitalocean_droplet.db]

  connection {
    type        = "ssh"
    host        = digitalocean_droplet.db.ipv4_address
    user        = "root"
    private_key = file("~/.ssh/id_rsa")
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "cloud-init status --wait",
      "echo 'Waiting for MSSQL...'",
      "SA_PASS=$(docker inspect mssql --format '{{range .Config.Env}}{{println .}}{{end}}' | grep MSSQL_SA_PASSWORD | cut -d= -f2)",
      "for i in $(seq 1 30); do docker exec mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P \"$SA_PASS\" -C -Q 'SELECT 1' > /dev/null 2>&1 && echo 'MSSQL is ready!' && break || echo \"  Waiting... ($i/30)\" && sleep 5; done"
    ]
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/restore-db.sh ${digitalocean_droplet.db.ipv4_address} $TF_VAR_mu_db_password"
  }
}


# -----------------------------------------------------------------------------
# Module: DB Firewall
# -----------------------------------------------------------------------------
resource "digitalocean_firewall" "db_firewall" {
  name = "${var.project_name}-db-firewall-${var.environment}"

  tags = [digitalocean_tag.roles["db"].name]

  # Allow MSSQL from web (always) and game (only if enabled) droplets
  inbound_rule {
    protocol   = "tcp"
    port_range = "1433"
    source_tags = var.enable_game_server ? [
      digitalocean_tag.roles["web"].name,
      digitalocean_tag.roles["game"].name
    ] : [
      digitalocean_tag.roles["web"].name
    ]
  }

  # Allow SSH from allowed IPs
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_allowed_ips
  }

  # Allow ICMP (ping) for debugging
  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow HTTPS out (to pull Docker images, updates)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "443"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow HTTP out
  outbound_rule {
    protocol              = "tcp"
    port_range            = "80"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow DNS out
  outbound_rule {
    protocol              = "udp"
    port_range            = "53"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# -----------------------------------------------------------------------------
# Module: DNS
# -----------------------------------------------------------------------------
resource "digitalocean_domain" "mu_domain" {
  name = var.domain_name
}

# Root domain → LB IP (production) or first web droplet IP (dev)
# Conditional value: if LB exists, use LB IP; otherwise use web droplet directly
resource "digitalocean_record" "root" {
  domain = digitalocean_domain.mu_domain.id
  type   = "A"
  name   = "@"
  value  = var.enable_load_balancer ? digitalocean_loadbalancer.web_lb[0].ip : digitalocean_droplet.web[0].ipv4_address
  ttl    = 300
}

# www → same conditional logic
resource "digitalocean_record" "www" {
  domain = digitalocean_domain.mu_domain.id
  type   = "A"
  name   = "www"
  value  = var.enable_load_balancer ? digitalocean_loadbalancer.web_lb[0].ip : digitalocean_droplet.web[0].ipv4_address
  ttl    = 300
}

# Direct droplet access for SSH/debugging (bypasses LB)
# count = var.web_droplet_count → one DNS record per web droplet
# web0.domain.com, web1.domain.com, web2.domain.com, ...
resource "digitalocean_record" "web_direct" {
  count = var.web_droplet_count

  domain = digitalocean_domain.mu_domain.id
  type   = "A"
  name   = "web${count.index}" # web0.yourdomain.com, web1.yourdomain.com, ...
  value  = digitalocean_droplet.web[count.index].ipv4_address
  ttl    = 300
}

# for_each with CONDITIONAL map — merge adds game entry only when enabled
# Combines for_each + conditional: a common real-world pattern
resource "digitalocean_record" "direct" {
  for_each = merge(
    { db = digitalocean_droplet.db.ipv4_address },                               # always
    var.enable_game_server ? { game = digitalocean_droplet.game[0].ipv4_address } : {}  # conditional
  )

  domain = digitalocean_domain.mu_domain.id
  type   = "A"
  name   = each.key    # "db" or "game" → db.danangmu.com, game.danangmu.com
  value  = each.value  # the droplet IP
  ttl    = 300
}
