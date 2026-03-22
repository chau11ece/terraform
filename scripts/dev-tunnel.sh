#!/bin/bash
# =============================================================================
# SSH Tunnel to Production MSSQL (for local website development)
# Opens local port 1433 → DB droplet's MSSQL container
# =============================================================================

DB_IP=$(terraform output -raw db_droplet_ip 2>/dev/null || echo "<DB_DROPLET_PUBLIC_IP>")

echo "Opening SSH tunnel to MSSQL at $DB_IP..."
echo "  Local port 1433 → DB droplet :1433"
echo "  Press Ctrl+C to close"
echo ""
echo "Then in another terminal:"
echo "  cd ../mu-online-web"
echo "  docker compose -f docker-compose.dev.yml up"
echo ""

ssh -N -L 1433:localhost:1433 root@$DB_IP
