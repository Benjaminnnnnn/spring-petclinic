#!/bin/bash

# Simple script to stop DevOps services
set -e

echo "Stopping DevOps services..."
docker compose -f docker-compose.devops.yml down

echo ""
echo "Services stopped successfully!"
echo ""
echo "To remove volumes as well, run:"
echo "  docker compose -f docker-compose.devops.yml down -v"
echo ""
