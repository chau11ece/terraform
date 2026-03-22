# MU Online Infrastructure - Terraform

Production-ready Terraform infrastructure for MU Online game server on DigitalOcean.

## Architecture

```
mu-infrastructure/
├── modules/
│   ├── networking/      # VPC, Firewalls, DNS, Load Balancer
│   ├── compute/         # Web & Game droplets
│   └── database/        # MSSQL database droplet
├── environments/
│   ├── dev/            # Development (minimal cost)
│   ├── staging/        # Staging environment
│   └── production/      # Production environment
└── scripts/             # Cloud-init scripts
```

## Quick Start

### 1. Setup Environment

```bash
# Navigate to your environment
cd environments/dev  # or staging or production

# Copy terraform.tfvars (update with your values)
cp terraform.tfvars.example terraform.tfvars

# Set sensitive variables
export TF_VAR_do_token="dop_v1_..."
export TF_VAR_mu_db_password="your_password"
export TF_VAR_mu_db_user="your_user"
```

### 2. Initialize Terraform

```bash
terraform init
terraform validate
terraform plan
```

### 3. Apply Changes

```bash
terraform apply
```

## Environments

| Environment | Load Balancer | Game Server | Web Droplets | Monthly Cost |
|-------------|--------------|-------------|--------------|--------------|
| **dev** | ❌ Off | ❌ Off | 1× s-1vcpu-1gb | ~$30 |
| **staging** | ✅ On | ✅ On | 1× s-1vcpu-1gb | ~$90 |
| **production** | ✅ On | ✅ On | 2× s-2vcpu-2gb | ~$180 |

## Module Structure

### modules/networking
- VPC configuration
- Load Balancer (optional)
- Firewalls (web, game, db)
- DNS records

### modules/compute
- Web droplets (scalable with count)
- Game droplets
- Game data volumes

### modules/database
- MSSQL database droplet
- Persistent volume for data

## Security

- SSH restricted to your IP only
- Database only accessible via private network
- Load balancer as only public entry point
- All secrets via environment variables

## Learn More

See the original [README](README-original.md) for detailed documentation.
