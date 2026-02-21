#!/usr/bin/env bash
# Single-shot feedback check — no blocking.
# Reads the anchor timestamp from .otto-last-post (or first arg).
# Exits 0 with feedback text on stdout if a reply exists; exits 1 if not.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

if [ ! -f .env.otto ]; then
	echo "ERROR: .env.otto not found." >&2
	exit 1
fi
source .env.otto

# Accept timestamp as arg or read from state file
if [ $# -ge 1 ]; then
	POSTED_AT="$1"
elif [ -f .otto-last-post ]; then
	POSTED_AT=$(cat .otto-last-post)
else
	echo "ERROR: no timestamp. Run 'npm run screenshot' first." >&2
	exit 1
fi

# Fetch the 50 most recent channel messages and look for any user reply
# after the anchor — top-level messages AND thread replies
MSGS=$(curl -s \
	"${OTTO_BASE_URL}/api/v1/channels/${OTTO_DEV_CHANNEL_ID}/messages?skip=0&limit=50" \
	-H "Authorization: Bearer ${OTTO_API_TOKEN}")

FEEDBACK=$(echo "$MSGS" | jq -r --argjson after "$POSTED_AT" '
	[.[] | select(.created_at > $after and .user.role == "user")]
	| sort_by(.created_at)
	| first
	| .content // empty
' 2>/dev/null || true)

if [ -n "$FEEDBACK" ]; then
	echo "$FEEDBACK"
	exit 0
fi

exit 1
