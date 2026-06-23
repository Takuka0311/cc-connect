#!/usr/bin/env bash
# Rebuild cc-connect (with embedded web UI) and restart the detached service.
#
# Usage:
#   scripts/cc-rebuild-restart.sh          # make build + ccctl restart + verify
#   scripts/cc-rebuild-restart.sh --no-verify   # skip HTTP / build-tag checks
#
# Overridable via env (same as ccctl.sh):
#   CC_BIN   path to the cc-connect binary (default: <repo>/cc-connect)
#   CC_LOG   log file (default: ~/.cc-connect/cc-connect.log)
#   CC_LOCK  instance lock file (default: ~/.cc-connect/.config.toml.lock)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${CC_BIN:-$REPO_DIR/cc-connect}"
VERIFY=1

for arg in "$@"; do
  case "$arg" in
    --no-verify) VERIFY=0 ;;
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "usage: $0 [--no-verify]" >&2
      exit 2
      ;;
  esac
done

cd "$REPO_DIR"
echo "==> make build (web frontend + binary)"
make build

echo "==> scripts/ccctl.sh restart"
"$REPO_DIR/scripts/ccctl.sh" restart

if [ "$VERIFY" -eq 1 ]; then
  echo "==> verify"
  "$REPO_DIR/scripts/ccctl.sh" status
  if go version -m "$BIN" 2>/dev/null | grep -q 'tags=no_web'; then
    echo "error: binary was built with no_web — web UI will 404 on /" >&2
    exit 1
  fi
  code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 http://127.0.0.1:9820/ || true)"
  echo "web UI http://127.0.0.1:9820/ -> HTTP $code"
  if [ "$code" != "200" ]; then
    echo "warning: expected HTTP 200; check [management] enabled and logs" >&2
    exit 1
  fi
fi

echo "done"
