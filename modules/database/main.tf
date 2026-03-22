# =============================================================================
# Database Module - Main
# Handles DB droplet and volumes
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
data "digitalocean_ssh_key" "deploy_key" {
  name = var.ssh_key_name
}

# -----------------------------------------------------------------------------
# Database Volume
# -----------------------------------------------------------------------------
resource "digitalocean_volume" "mssql_data" {
  region                  = var.region
  name                    = "${var.project_name}-mssql-data"
  size                    = var.db_volume_size
  initial_filesystem_type = "ext4"
  description             = "Persistent MSSQL data"

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Database Droplet
# -----------------------------------------------------------------------------
resource "digitalocean_droplet" "db" {
  name       = "${var.project_name}-db-${var.environment}"
  image      = var.web_droplet_image
  size       = var.db_droplet_size
  region     = var.region
  vpc_uuid   = var.vpc_uuid
  ssh_keys   = [data.digitalocean_ssh_key.deploy_key.id]
  volume_ids = [digitalocean_volume.mssql_data.id]

  user_data = templatefile("${path.module}/scripts/db-init.sh", {
    mu_db_password = var.mu_db_password,
    volume_name    = digitalocean_volume.mssql_data.name,
  })

  tags = [
    var.project_name,
    var.db_tag_name,
    var.environment
  ]

  lifecycle {
    prevent_destroy = false
  }
}

# -----------------------------------------------------------------------------
# Optional: Provisioners (wait for DB to be ready)
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
    command = "${path.module}/../scripts/restore-db.sh ${digitalocean_droplet.db.ipv4_address} $TF_VAR_mu_db_password"
  }
}
