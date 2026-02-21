#!/usr/bin/env python3
"""Take UI screenshots of Open WebUI for the feedback loop."""

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

from playwright.sync_api import sync_playwright

# --- Config ---

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent

env: dict[str, str] = {}
env_file = PROJECT_DIR / ".env.otto"
for line in env_file.read_text().splitlines():
    if "=" in line and not line.startswith("#"):
        k, _, v = line.partition("=")
        env[k.strip()] = v.strip()

BASE_URL = env.get("OTTO_BASE_URL", "http://localhost:3100").rstrip("/")
ADMIN_EMAIL = env.get("WEBUI_ADMIN_EMAIL", "admin@example.com")
ADMIN_PASSWORD = env.get("WEBUI_ADMIN_PASSWORD", "password")

OUTPUT_DIR = PROJECT_DIR / "playwright-screenshots"
OUTPUT_DIR.mkdir(exist_ok=True)


# --- Auth ---

def api_post(path: str, body: dict) -> tuple[dict, int]:
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f"{BASE_URL}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read()), resp.status
    except urllib.error.HTTPError as e:
        return json.loads(e.read()), e.code


# Register admin (idempotent — 400 if already exists)
api_post("/api/v1/auths/signup", {
    "name": "Admin User",
    "email": ADMIN_EMAIL,
    "password": ADMIN_PASSWORD,
})

auth, status = api_post("/api/v1/auths/signin", {
    "email": ADMIN_EMAIL,
    "password": ADMIN_PASSWORD,
})
if status != 200:
    print(f"ERROR: Login failed ({status}): {auth}", file=sys.stderr)
    sys.exit(1)

token: str = auth["token"]
print(f"Logged in as {ADMIN_EMAIL}")

SHOT_OPTS = {"timeout": 60_000, "animations": "disabled"}


# --- Screenshots ---

with sync_playwright() as p:
    browser = p.chromium.launch(args=["--font-render-hinting=none"])
    ctx = browser.new_context(viewport={"width": 1440, "height": 900})
    page = ctx.new_page()

    # Bootstrap: visit app and set auth token in localStorage
    page.goto(BASE_URL)
    page.wait_for_load_state("load")
    page.evaluate("""(token) => {
        localStorage.setItem('token', token);
        localStorage.setItem('locale', 'en-US');
    }""", token)

    # Navigate to home — wait for chat input to confirm app is ready
    page.goto(BASE_URL)
    page.wait_for_load_state("load")
    page.wait_for_selector("#chat-input", timeout=20000)

    # Dismiss changelog modal if present
    try:
        ok_btn = page.get_by_role("button", name="Okay, Let's Go!")
        if ok_btn.is_visible():
            ok_btn.click()
            page.wait_for_timeout(500)
    except Exception:
        pass

    # Home — new chat screen
    page.screenshot(path=str(OUTPUT_DIR / "home.png"), full_page=True, **SHOT_OPTS)
    print("✓ home")

    # Sidebar — expand if collapsed, then screenshot
    try:
        toggle = page.get_by_label("Open sidebar")
        if toggle.is_visible():
            toggle.click()
            page.wait_for_timeout(600)
    except Exception:
        pass
    page.screenshot(path=str(OUTPUT_DIR / "sidebar.png"), full_page=True, **SHOT_OPTS)
    print("✓ sidebar")

    # Settings — open settings modal via user menu
    try:
        page.get_by_role("button", name="User menu").click()
        page.wait_for_timeout(500)
        page.get_by_text("Settings").first.click()
        page.wait_for_timeout(1000)
    except Exception as e:
        print(f"  (settings modal open failed: {e})", file=sys.stderr)
    page.screenshot(path=str(OUTPUT_DIR / "settings.png"), full_page=True, **SHOT_OPTS)
    print("✓ settings")

    browser.close()

print(f"\nSaved to {OUTPUT_DIR}/")
