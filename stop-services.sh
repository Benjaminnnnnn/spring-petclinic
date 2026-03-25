#!/bin/bash

# Simple script to stop DevSecOps services
set -e

echo "Stopping DevSecOps services..."
docker compose -f docker-compose-devsecops.yml down

echo ""
echo "Services stopped successfully!"
echo ""
echo "To remove volumes as well, run:"
echo "  docker compose -f docker-compose-devsecops.yml down -v"
echo ""
