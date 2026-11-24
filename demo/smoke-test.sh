#!/usr/bin/env bash
# Run the release bundle the way a user would and check the Lean engine
# reacts to Home Assistant. The HALean image the bundle pins must already be
# local (it is tested before it is published); Home Assistant is pulled.
#
#   demo/smoke-test.sh dist/halean-demo.tar.gz [PORT]
set -euo pipefail

bundle="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
port="${2:-8199}"
project=halean-smoke
work="$(mktemp -d)"
cd "$work"
tar xzf "$bundle"
cd halean-demo

compose() { DEMO_PORT="$port" docker compose -p "$project" "$@"; }
cleanup() {
  compose down -v >/dev/null 2>&1 || true
  cd / && rm -r "$work" 2>/dev/null || true
}
trap cleanup EXIT

compose up -d --pull missing

for _ in $(seq 1 100); do
  if compose logs halean 2>/dev/null | grep -q 'INFO triggered '; then
    compose logs halean | grep -E 'engine running|triggered' | head -5
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/halean-demo")
    [ "$code" = 200 ] || { echo "dashboard returned HTTP $code"; exit 1; }
    echo "smoke test passed"
    exit 0
  fi
  sleep 3
done

echo "engine never triggered an automation within 5 minutes"
compose logs --tail 60
exit 1
