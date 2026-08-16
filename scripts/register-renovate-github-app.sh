#!/usr/bin/env bash
# Registers the Renovate bot GitHub App via the manifest flow
# (https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)
# and stores the resulting credentials in 1Password. The private key and
# client secret are never printed -- they go straight from the GitHub API
# response into `op`, held only in memory in between.
#
# The one step this script can't skip: GitHub requires you to review and
# click "Create GitHub App" yourself in your own logged-in browser. This
# script opens that page for you and waits for the redirect back.
set -euo pipefail

APP_NAME="alex-trend-bot"
REPO_URL="https://github.com/alexmathieu22/home-ops"
VAULT="home-ops"
ITEM_TITLE="github-bot"
PORT=18234
REDIRECT_URL="http://localhost:${PORT}/callback"
CALLBACK_TIMEOUT=300 # seconds to wait for the browser round-trip

for bin in curl jq nc op open lsof; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Missing required tool: $bin" >&2
    exit 1
  fi
done

echo "Checking 1Password CLI sign-in..."
if ! op whoami >/dev/null 2>&1; then
  echo "Not signed in to 1Password CLI. Run:" >&2
  echo "  eval \$(op signin)" >&2
  echo "then re-run this script." >&2
  exit 1
fi
if op whoami 2>/dev/null | grep -q SERVICE_ACCOUNT; then
  echo "Signed in as a 1Password service account, which is typically read-only." >&2
  echo "This script needs write access to create the 1Password item. Run:" >&2
  echo "  unset OP_SERVICE_ACCOUNT_TOKEN && eval \$(op signin)" >&2
  echo "to switch to your personal account, then re-run this script." >&2
  exit 1
fi
echo "Signed in to 1Password."

if ! op vault get "$VAULT" >/dev/null 2>&1; then
  echo "Cannot access 1Password vault '$VAULT' (check the name and your permissions)." >&2
  exit 1
fi
echo "Vault '$VAULT' is accessible."

if lsof -i ":${PORT}" >/dev/null 2>&1; then
  echo "Port ${PORT} is already in use -- free it or edit PORT in this script." >&2
  exit 1
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

MANIFEST_JSON=$(jq -n \
  --arg name "$APP_NAME" \
  --arg url "$REPO_URL" \
  --arg redirect_url "$REDIRECT_URL" \
  '{
    name: $name,
    url: $url,
    redirect_url: $redirect_url,
    public: false,
    default_events: [],
    default_permissions: {
      contents: "write",
      pull_requests: "write",
      issues: "write",
      checks: "write",
      statuses: "write",
      workflows: "write",
      metadata: "read"
    }
  }')
# hook_attributes is omitted entirely -- including it without a url (even just
# {active: false}) fails GitHub's manifest validation with "url wasn't supplied".

HTML_FILE="$WORKDIR/register.html"
MANIFEST_ESCAPED=$(printf '%s' "$MANIFEST_JSON" | sed "s/'/\&apos;/g")
cat >"$HTML_FILE" <<HTML
<!doctype html>
<html>
<body onload="document.forms[0].submit()">
  <p>Redirecting to GitHub to review the new app...</p>
  <form action="https://github.com/settings/apps/new" method="post">
    <input type="hidden" name="manifest" value='${MANIFEST_ESCAPED}'>
  </form>
</body>
</html>
HTML

RESP_FILE="$WORKDIR/response.txt"
cat >"$RESP_FILE" <<'HTTP'
HTTP/1.1 200 OK
Content-Type: text/html
Connection: close

<html><body><h1>GitHub App created &mdash; you can close this tab.</h1></body></html>
HTTP

REQ_FILE="$WORKDIR/request.txt"
nc -l "$PORT" <"$RESP_FILE" >"$REQ_FILE" &
NC_PID=$!
(
  sleep "$CALLBACK_TIMEOUT"
  kill "$NC_PID" 2>/dev/null
) &
WATCHDOG_PID=$!

echo "Opening browser -- review the app on GitHub and click 'Create GitHub App'."
open "$HTML_FILE"
echo "Waiting up to ${CALLBACK_TIMEOUT}s for the redirect back to ${REDIRECT_URL}..."

wait "$NC_PID" 2>/dev/null || true
kill "$WATCHDOG_PID" 2>/dev/null || true

CODE=$(grep -oE '^GET /callback\?code=[^ ]+' "$REQ_FILE" | sed -E 's#^GET /callback\?code=##') || true
if [[ -z "${CODE:-}" ]]; then
  echo "No callback received -- did you complete the GitHub review page? Re-run to try again." >&2
  exit 1
fi

echo "Exchanging code for app credentials..."
CONVERSION=$(curl -s -X POST "https://api.github.com/app-manifests/${CODE}/conversions" \
  -H "Accept: application/vnd.github+json")

APP_SLUG=$(echo "$CONVERSION" | jq -r '.slug // empty')
APP_ID=$(echo "$CONVERSION" | jq -r '.id // empty')
CLIENT_ID=$(echo "$CONVERSION" | jq -r '.client_id // empty')
PEM=$(echo "$CONVERSION" | jq -r '.pem // empty')

if [[ -z "$APP_SLUG" || -z "$CLIENT_ID" || -z "$PEM" ]]; then
  echo "Conversion response was missing expected fields -- the code is single-use and short-lived, re-run this script." >&2
  exit 1
fi

echo "App created: ${APP_SLUG} (id ${APP_ID})"
echo "Storing credentials in 1Password vault '${VAULT}', item '${ITEM_TITLE}'..."

if op item get "$ITEM_TITLE" --vault "$VAULT" >/dev/null 2>&1; then
  op item edit "$ITEM_TITLE" --vault "$VAULT" \
    "GITHUB_BOT_APP_CLIENT_ID=${CLIENT_ID}" \
    "GITHUB_BOT_APP_PRIVATE_KEY=${PEM}" >/dev/null
else
  op item create --vault "$VAULT" --category "API Credential" --title "$ITEM_TITLE" \
    "GITHUB_BOT_APP_CLIENT_ID[text]=${CLIENT_ID}" \
    "GITHUB_BOT_APP_PRIVATE_KEY[text]=${PEM}" >/dev/null
fi

unset PEM CLIENT_ID CONVERSION

echo "Done -- credentials stored in 1Password (not printed here)."
echo ""
echo "Next: install the app on the repo:"
echo "  https://github.com/apps/${APP_SLUG}/installations/new"
