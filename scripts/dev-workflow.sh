#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

if [ ! -f .env.otto ]; then
	echo "ERROR: .env.otto not found. Copy .env.otto.example and fill in your values." >&2
	exit 1
fi
source .env.otto

SCREENSHOT_ONLY=false
NO_POST=false

for arg in "$@"; do
	[[ "$arg" == "--screenshot-only" ]] && SCREENSHOT_ONLY=true
	[[ "$arg" == "--no-post" ]]        && NO_POST=true
done

if ! $SCREENSHOT_ONLY; then
	echo "=== 1. Type check ==="
	npm run check

	echo "=== 2. Unit tests ==="
	npm run test:frontend
fi

echo "=== 4. Screenshots ==="
python3 scripts/take-screenshots.py

if ! $NO_POST; then
	echo "=== 5. Post screenshots ==="
	bash scripts/post-channel.sh --dir=playwright-screenshots >&2
	echo ""
	echo "Screenshots posted. Run 'npm run check-feedback' to read replies."
fi
