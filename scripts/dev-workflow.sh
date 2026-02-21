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

	echo "=== 3. Cypress E2E ==="
	E2E_EXIT=0
	CYPRESS_BASE_URL="${OTTO_BASE_URL:-http://localhost:3100}" npx cypress run || E2E_EXIT=$?
	if [ "$E2E_EXIT" -ne 0 ]; then
		echo "WARNING: Cypress E2E tests failed (exit $E2E_EXIT) — proceeding to screenshots" >&2
	fi
fi

echo "=== 4. Screenshots ==="
CYPRESS_BASE_URL="${OTTO_BASE_URL:-http://localhost:3100}" npx cypress run \
	--spec "cypress/e2e/screenshots.cy.ts" \
	--browser chrome

if ! $NO_POST; then
	echo "=== 5. Post + wait for feedback ==="
	FEEDBACK=$(bash scripts/post-channel.sh --dir=cypress/screenshots)
	echo ""
	echo "=== USER FEEDBACK ==="
	echo "$FEEDBACK"
	echo "====================="
fi
