#!/usr/bin/env bash
# Build the standalone demo bundle attached to each GitHub release:
# docker-compose.yml pinned to one image version, the HA config and the
# automations. No checkout and no Lean toolchain needed to run it.
#
#   demo/make-bundle.sh 0.1.0 dist     # -> dist/halean-demo.tar.gz
set -euo pipefail

version="${1:?usage: make-bundle.sh VERSION [OUTDIR]}"
out="${2:-dist}"
here="$(cd "$(dirname "$0")" && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
b="$stage/halean-demo"

mkdir -p "$b/ha" "$out"
cp "$here/ha/configuration.yaml" "$here/ha/ui-lovelace.yaml" "$b/ha/"
cp "$here/automations.yaml" "$b/"

# Same compose file as the repo, minus the local build, pinned to $version.
grep -v '^    build: ' "$here/docker-compose.yml" \
  | sed -e "s/HALEAN_VERSION:-latest/HALEAN_VERSION:-$version/g" \
        -e '/--build/d' -e 's#cd demo && ##' \
  > "$b/docker-compose.yml"
grep -q "halean:\${HALEAN_VERSION:-$version}" "$b/docker-compose.yml"
if grep -q 'build:' "$b/docker-compose.yml"; then echo "bundle still builds locally" >&2; exit 1; fi

cat > "$b/README.md" <<EOF
# HALean demo $version

A stock Home Assistant whose automations all run in the Lean engine.

    docker compose up -d

Open <http://localhost:8124/halean-demo>. The login is written to
\`.run/login.txt\` on the first start. Use another port with
\`DEMO_PORT=8200 docker compose up -d\`.

* \`automations.yaml\`: the automations the Lean engine runs. Edit it, then
  \`docker compose restart halean\`.
* Stop: \`docker compose down\`. Start over: \`docker compose down -v\`.

Images: ghcr.io/beneficial-ai-foundation/halean:$version (linux/amd64, linux/arm64)
Source: https://github.com/Beneficial-AI-Foundation/halean/tree/v$version
EOF

tar -C "$stage" -czf "$out/halean-demo.tar.gz" halean-demo
echo "$out/halean-demo.tar.gz"
