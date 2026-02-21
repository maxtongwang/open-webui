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

BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
SCREENSHOT_DIR="playwright-screenshots"

for arg in "$@"; do
	[[ "$arg" == --dir=* ]] && SCREENSHOT_DIR="${arg#--dir=}"
done

# Post header message
curl -s -X POST \
	"${OTTO_BASE_URL}/api/v1/channels/${OTTO_DEV_CHANNEL_ID}/messages/post" \
	-H "Authorization: Bearer ${OTTO_API_TOKEN}" \
	-H "Content-Type: application/json" \
	-d "$(jq -n --arg content "📸 Screenshots — branch \`${BRANCH}\` @ ${TIMESTAMP}" '{content: $content}')" \
	> /dev/null

# Anchor timestamp (nanoseconds, matches Open WebUI created_at)
POSTED_AT=$(( $(date +%s) * 1000000000 ))

# Upload + post each screenshot
FOUND=0
while IFS= read -r -d '' SHOT; do
	[ -f "$SHOT" ] || continue
	NAME=$(basename "$SHOT" .png)
	FOUND=$(( FOUND + 1 ))

	RESP=$(curl -s -X POST "${OTTO_BASE_URL}/api/v1/files/" \
		-H "Authorization: Bearer ${OTTO_API_TOKEN}" \
		-F "file=@${SHOT};type=image/png")

	FILE_ID=$(echo "$RESP" | jq -r '.id // empty')
	if [ -z "$FILE_ID" ]; then
		>&2 echo "Upload failed for $NAME: $RESP"
		continue
	fi

	curl -s -X POST \
		"${OTTO_BASE_URL}/api/v1/channels/${OTTO_DEV_CHANNEL_ID}/messages/post" \
		-H "Authorization: Bearer ${OTTO_API_TOKEN}" \
		-H "Content-Type: application/json" \
		-d "$(jq -n \
			--arg name "$NAME" \
			--arg id "$FILE_ID" \
			'{content: ("`" + $name + "`"), data: {files: [{id: $id, type: "image", url: $id, content_type: "image/png"}]}}')" \
		> /dev/null

	>&2 echo "Posted: $NAME"
done < <(find "$SCREENSHOT_DIR" -name "*.png" -print0 2>/dev/null)

if [ "$FOUND" -eq 0 ]; then
	>&2 echo "No screenshots found under $SCREENSHOT_DIR"
	exit 1
fi

# Update anchor to after all screenshots were posted
POSTED_AT=$(( $(date +%s) * 1000000000 ))

# Save anchor for check-feedback.sh
echo "$POSTED_AT" > .otto-last-post

>&2 echo "Posted $FOUND screenshot(s). Run 'npm run check-feedback' to read replies."
echo "$POSTED_AT"
