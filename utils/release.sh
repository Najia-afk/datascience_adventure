#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RESET_STATIC_VOLUME=false
SKIP_PULL=false
SKIP_SMOKE=false
BASE_URL="http://localhost"

for arg in "$@"; do
    case "$arg" in
        --reset-static-volume)
            RESET_STATIC_VOLUME=true
            ;;
        --skip-pull)
            SKIP_PULL=true
            ;;
        --skip-smoke)
            SKIP_SMOKE=true
            ;;
        --base-url=*)
            BASE_URL="${arg#*=}"
            ;;
        -h|--help)
            cat <<'HELP'
Usage: ./utils/release.sh [options]

Options:
  --reset-static-volume   Remove datascience_adventure_static_data before rebuild
  --skip-pull             Skip git pull
  --skip-smoke            Skip HTTP smoke checks
  --base-url=<url>        Base URL for smoke checks (default: http://localhost)
  -h, --help              Show this help message
HELP
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Run ./utils/release.sh --help"
            exit 1
            ;;
    esac
done

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1"
        exit 1
    fi
}

require_cmd docker
require_cmd git
require_cmd python3

echo "==> Releasing from: $ROOT_DIR"

if [ "$SKIP_PULL" = false ]; then
    echo "==> Syncing repository (git pull --ff-only)"
    git fetch --all --prune
    git pull --ff-only
else
    echo "==> Skipping git pull"
fi

echo "==> Validating article sidecars"
python3 utils/scripts/validate_article_sidecars.py app/static/templates

echo "==> Stopping running stack"
docker compose down

if [ "$RESET_STATIC_VOLUME" = true ]; then
    echo "==> Resetting static volume"
    docker volume rm datascience_adventure_static_data || true
fi

echo "==> Building and recreating containers"
docker compose up -d --build --force-recreate

echo "==> Container status"
docker compose ps

if [ "$SKIP_SMOKE" = false ]; then
    if command -v curl >/dev/null 2>&1; then
        echo "==> Running smoke checks against $BASE_URL"
        for path in "/" "/summary" "/header"; do
            curl -fsSL "${BASE_URL}${path}" >/dev/null
            echo "   OK ${path}"
        done
    else
        echo "==> curl not found; skipping smoke checks"
    fi
else
    echo "==> Skipping smoke checks"
fi

echo "==> Release complete ✅"
