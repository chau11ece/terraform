# MU Online Packer Snapshots

## Why Use Custom Snapshots?

**Problem:** Every `terraform apply` boots a blank Ubuntu droplet and runs a 5-10 minute setup script (install Docker, Wine, ODBC, etc.)

**Solution:** Pre-bake everything into custom DigitalOcean snapshots. Droplets boot in 30-60 seconds instead of 5-10 minutes.

## What's Included

- **`mu-web-base.pkr.hcl`** — Web server with Docker + pre-pulled `chaudevops/mu-web:latest`
- **`mu-db-base.pkr.hcl`** — Database server with Docker + pre-pulled MSSQL 2022 image
- **`mu-game-base.pkr.hcl`** — Game server with Wine + ODBC + FreeTDS pre-configured

## Prerequisites

1. **Install Packer**
   ```bash
   # macOS
   brew install packer

   # Linux (or download from packer.io)
   curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
   sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
   sudo apt-get update && sudo apt-get install packer
   ```

2. **Get your DigitalOcean API token**
   - Go to: https://cloud.digitalocean.com/account/api/tokens
   - Generate new token (read + write)
   - Export it:
     ```bash
     export DIGITALOCEAN_TOKEN=dop_v1_abc123...
     ```

## Build Snapshots

```bash
# Validate templates (check syntax)
make validate

# Build all 3 snapshots (takes ~15-20 minutes total)
make all

# Or build individually
make web   # ~5 min
make db    # ~7 min (MSSQL image is large)
make game  # ~8 min (Wine setup is slow)
```

## What Happens During Build

Packer will:
1. Create a temporary droplet on DigitalOcean
2. SSH into it and run provisioning scripts
3. Take a snapshot of the configured droplet
4. Destroy the temporary droplet
5. Leave you with a reusable snapshot

**Cost:** ~$0.01 per build (temporary droplet runs for 10-15 min)

**Snapshot storage:** $0.05/GB/month (snapshots are ~5-10 GB each = ~$0.25-0.50/month)

## Use Snapshots in Terraform

1. **After building, check the snapshot IDs:**
   ```bash
   cat manifest-web.json | jq .builds[0].artifact_id
   # Output: sgp1:123456789
   ```

2. **Copy `snapshots.tf` to your Terraform directory:**
   ```bash
   cp snapshots.tf ../snapshots.tf
   ```

3. **Update your droplet resources in `main.tf`:**
   ```hcl
   resource "digitalocean_droplet" "web" {
     count = var.web_droplet_count

     name     = "${var.project_name}-web-${var.environment}-${count.index}"
     image    = data.digitalocean_image.mu_web_base.id  # ← Changed from var.web_droplet_image
     size     = var.web_droplet_size
     region   = var.region
     # ... rest stays the same
   }

   resource "digitalocean_droplet" "db" {
     name  = "${var.project_name}-db-${var.environment}"
     image = data.digitalocean_image.mu_db_base.id  # ← Changed
     # ... rest stays the same
   }

   resource "digitalocean_droplet" "game" {
     count = var.enable_game_server ? 1 : 0
     name  = "${var.project_name}-game-${var.environment}"
     image = data.digitalocean_image.mu_game_base.id  # ← Changed
     # ... rest stays the same
   }
   ```

4. **Simplify your cloud-init scripts:**

   Since Docker/Wine are pre-installed, your `*-init.sh` scripts can skip installation steps:

   **Before (web-init.sh):**
   ```bash
   # Install Docker (takes 2-3 min)
   apt-get install -y docker-ce ...
   docker pull chaudevops/mu-web:latest  # (takes 1-2 min)
   docker run ...
   ```

   **After (web-init.sh):**
   ```bash
   # Docker already installed, image already pulled
   docker run ...  # (starts immediately)
   ```

5. **Test it:**
   ```bash
   terraform plan   # Should show using data.digitalocean_image.mu_web_base
   terraform apply  # Droplets boot in 30-60s instead of 5-10 min
   ```

## Updating Snapshots

When you update packages or configurations, rebuild the snapshots:

```bash
# Example: You updated to a newer Wine version
cd packer/
make game  # Builds new mu-game-base-YYYYMMDD snapshot

# Terraform automatically uses the newest snapshot (lexicographically)
# No code changes needed, just terraform apply
```

## Snapshot Lifecycle

- **Keep 2-3 recent snapshots** (for rollback if needed)
- **Delete old snapshots** to save $0.05/GB/month:
  ```bash
  # Via DO console: Images → Snapshots → Delete
  # Or via CLI: doctl compute snapshot delete SNAPSHOT_ID
  ```

## Troubleshooting

**Error: "snapshot not found"**
- Run `make all` first to create snapshots
- Check DO console: Images → Snapshots
- Verify snapshot names match `mu-*-base-*` pattern

**Error: "API token invalid"**
- Check: `echo $DIGITALOCEAN_TOKEN`
- Re-export: `export DIGITALOCEAN_TOKEN=dop_v1_...`

**Packer hangs at "Waiting for SSH"**
- Check DO firewall rules allow SSH (port 22)
- Verify your account isn't rate-limited

## Cost Comparison

**Without snapshots (current):**
- Every `terraform apply` = 5-10 min of cloud-init
- Can't scale fast (each new droplet waits for setup)

**With snapshots:**
- First-time setup: ~$0.01 to build + $0.25/month storage
- Every `terraform apply` = 30-60 seconds
- Can scale instantly (spin up 10 web droplets in parallel)

**Break-even:** After ~2-3 deploys, snapshots save time and money
