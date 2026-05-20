#!/bin/bash
# DevContainer setup script
# Runs after container creation

set -e

echo "=== OpenTenBase Development Environment Setup ==="

# Configure git
git config --global --add safe.directory /workspace

# Check build tools
echo "Checking build tools..."
for tool in gcc make bison flex perl; do
    if command -v "$tool" &>/dev/null; then
        echo "  ✓ $tool: $(command -v $tool)"
    else
        echo "  ✗ $tool: not found"
    fi
done

# Check libraries
echo ""
echo "Checking libraries..."
for lib in libreadline-dev zlib1g-dev libssl-dev libxml2-dev; do
    if dpkg -s "$lib" &>/dev/null; then
        echo "  ✓ $lib: installed"
    else
        echo "  ✗ $lib: not installed"
    fi
done

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Quick start:"
echo "  cd scripts/"
echo "  sudo bash build-deb.sh /path/to/opentenbase-source /output"
echo ""
echo "Or use Docker:"
echo "  docker compose -f docker/compose/docker-compose.yml up -d"
