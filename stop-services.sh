#!/bin/bash

set -euo pipefail

COMPOSE_FILE="docker-compose.devops.yml"
REMOVE_VOLUMES=false

usage() {
    cat <<EOF
Usage: ./stop-services.sh [--volume]

Options:
  --volume    Stop services and remove Docker volumes
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --volume)
            REMOVE_VOLUMES=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

echo "Stopping DevOps services..."
if [ "$REMOVE_VOLUMES" = true ]; then
    docker compose -f "$COMPOSE_FILE" down -v
else
    docker compose -f "$COMPOSE_FILE" down
fi

echo ""
echo "Services stopped successfully!"
echo ""
if [ "$REMOVE_VOLUMES" = false ]; then
    echo "To remove volumes as well, run:"
    echo "  ./stop-services.sh --volume"
    echo ""
fi
