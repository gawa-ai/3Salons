#!/usr/bin/env bash
# Build the site from GitHub main and publish it into ./site. Safe to run any time; keeps the old site if the build fails.
# Usage: ./deploy.sh [--if-changed]
set -euo pipefail
cd "$(dirname "$0")"
exec 9>.deploy.lock; flock -n 9 || { echo "deploy already running"; exit 0; }
REPO=https://github.com/gawa-ai/3Salons.git
[ -d src/.git ] || git clone -q --depth 1 "$REPO" src
git -C src fetch -q --depth 1 origin main
NEW=$(git -C src rev-parse FETCH_HEAD); OLD=$(cat .deployed 2>/dev/null || true)
if [ "${1:-}" = "--if-changed" ] && [ "$NEW" = "$OLD" ]; then exit 0; fi
git -C src reset -q --hard "$NEW"
echo "building $NEW"
docker run --rm -v "$PWD/src/web":/app -w /app node:22-alpine sh -c 'npm install --no-audit --no-fund --loglevel=error && npm run check'
[ -s src/web/dist/index.html ] || { echo "build produced no index.html"; exit 1; }
mkdir -p site
rsync -a --delete src/web/dist/ site/ 2>/dev/null || { find site -mindepth 1 -delete; cp -a src/web/dist/. site/; }
echo "$NEW" > .deployed
echo "deployed $NEW"
