# Makefile for building MU Online Packer snapshots
#
# Prerequisites:
# 1. Install Packer: brew install packer (macOS) or download from packer.io
# 2. Set DO token: export DIGITALOCEAN_TOKEN=dop_v1_xxx...
#
# Usage:
#   make all         # Build all 3 snapshots (web, db, game)
#   make web         # Build only web snapshot
#   make db          # Build only db snapshot
#   make game        # Build only game snapshot
#   make validate    # Validate all templates without building
#   make clean       # Remove manifest files

.PHONY: all web db game validate clean help

# Check if Packer is installed
PACKER := $(shell command -v packer 2> /dev/null)
ifndef PACKER
$(error "packer not found. Install: brew install packer (macOS) or download from packer.io")
endif

# Check if DO token is set
ifndef DIGITALOCEAN_TOKEN
$(error "DIGITALOCEAN_TOKEN not set. Export it: export DIGITALOCEAN_TOKEN=dop_v1_...")
endif

all: web db game
	@echo "\n✅ All snapshots built successfully!"
	@echo "Next steps:"
	@echo "  1. Check DigitalOcean console for new snapshots"
	@echo "  2. Note the snapshot IDs from manifest-*.json"
	@echo "  3. Update terraform variables to use these snapshots"

web:
	@echo "🔨 Building web base snapshot..."
	packer build mu-web-base.pkr.hcl
	@echo "✅ Web snapshot created. Check manifest-web.json for snapshot ID"

db:
	@echo "🔨 Building database base snapshot..."
	packer build mu-db-base.pkr.hcl
	@echo "✅ DB snapshot created. Check manifest-db.json for snapshot ID"

game:
	@echo "🔨 Building game base snapshot..."
	packer build mu-game-base.pkr.hcl
	@echo "✅ Game snapshot created. Check manifest-game.json for snapshot ID"

validate:
	@echo "✓ Validating mu-web-base.pkr.hcl..."
	@packer validate mu-web-base.pkr.hcl
	@echo "✓ Validating mu-db-base.pkr.hcl..."
	@packer validate mu-db-base.pkr.hcl
	@echo "✓ Validating mu-game-base.pkr.hcl..."
	@packer validate mu-game-base.pkr.hcl
	@echo "✅ All templates valid"

clean:
	rm -f manifest-*.json
	rm -rf packer_cache/

help:
	@echo "MU Online Packer Snapshot Builder"
	@echo ""
	@echo "Targets:"
	@echo "  make all       - Build all 3 snapshots (takes ~15-20 min)"
	@echo "  make web       - Build web snapshot only (~5 min)"
	@echo "  make db        - Build database snapshot only (~7 min)"
	@echo "  make game      - Build game snapshot only (~8 min)"
	@echo "  make validate  - Validate all Packer templates"
	@echo "  make clean     - Remove build artifacts"
	@echo ""
	@echo "Prerequisites:"
	@echo "  1. Install Packer: brew install packer"
	@echo "  2. Set token: export DIGITALOCEAN_TOKEN=dop_v1_..."
	@echo ""
	@echo "Current status:"
	@echo "  Packer: $(PACKER)"
	@echo "  DO Token: $(if $(DIGITALOCEAN_TOKEN),✅ Set,❌ Not set)"
