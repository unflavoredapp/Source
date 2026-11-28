#!/usr/bin/env bash
# Install Node deps + PM2 and start the IPA relay on a VPS.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v node >/dev/null 2>&1; then
  echo "Node 18+ required. Install Node, then re-run."
  exit 1
fi

echo "→ npm install (teleproto / GramJS + dotenv)"
npm install

if ! command -v pm2 >/dev/null 2>&1; then
  echo "→ installing pm2 globally"
  npm install -g pm2
fi

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env from .env.example — edit it, then:"
  echo "  1) npm run login          # api_id / api_hash / phone (AirShare-style)"
  echo "  2) set TELEGRAM_CHANNEL_ID + TELEGRAM_BOT_TOKEN + RELAY_TOKEN + PUBLIC_BASE_URL"
  echo "  3) ./setup-vps.sh         # again to start PM2"
  exit 0
fi

missing=0
for key in RELAY_TOKEN PUBLIC_BASE_URL TELEGRAM_API_ID TELEGRAM_API_HASH TELEGRAM_SESSION TELEGRAM_CHANNEL_ID TELEGRAM_BOT_TOKEN; do
  if ! grep -qE "^${key}=.+" .env; then
    echo "Missing $key in .env"
    missing=1
  fi
done
if [[ "$missing" -ne 0 ]]; then
  echo "Fill .env (npm run login for SESSION), then re-run."
  exit 1
fi

echo "→ pm2 start ecosystem.config.cjs"
pm2 start ecosystem.config.cjs
pm2 save
echo "Done. Useful commands:"
echo "  pm2 logs unlicense-ipa-relay"
echo "  pm2 restart unlicense-ipa-relay"
echo "  curl -s localhost:${PORT:-8787}/health"
