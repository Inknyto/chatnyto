#!/usr/bin/env bash
# One command to deploy the ChatNyto MQTT broker to the VPS.
#
#   ./deploy/deploy-remote.sh              # push HEAD and deploy
#   ./deploy/deploy-remote.sh --no-push    # deploy what is already on the branch
#   ./deploy/deploy-remote.sh users        # only rewrite the broker accounts
#
# Run from YOUR machine, never on the server. What it does:
#   1. pushes the current branch to the git remote
#   2. server: git fetch + hard reset to that branch
#   3. RENDERS deploy/.env.prod locally — entries may be $(pass show …), and
#      those substitutions run here, where your gpg key lives, never on the
#      server — then streams the resolved values into a tmpfs file
#   4. server: ./deploy/deploy.sh, which starts mosquitto plus the tunnel and
#      health-checks the broker; the tmpfs secrets are removed either way
#
# Config: deploy/deploy.conf (see deploy.conf.example) or environment vars.
set -euo pipefail

cd "$(dirname "$0")/.."

CONF="deploy/deploy.conf"
[ -f "$CONF" ] && . "$CONF"

: "${DEPLOY_HOST:?Set DEPLOY_HOST in deploy/deploy.conf (server IP or hostname)}"
: "${DEPLOY_PORT:=22}"
: "${DEPLOY_USER:?Set DEPLOY_USER in deploy/deploy.conf (non-root SSH user)}"
: "${DEPLOY_DIR:=/opt/chatnyto}"
: "${DEPLOY_BRANCH:=main}"
: "${GIT_REMOTE:=origin}"
: "${SSH_KEY:=$HOME/.ssh/id_ed25519_hetzner}"

ENV_FILE="deploy/.env.prod"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found. Copy deploy/.env.prod.example and fill in real secrets." >&2
  exit 1
fi

# Compose env files are not shell-evaluated, so resolve $(pass …) and $VAR
# here and re-emit plain KEY=value lines. Values must be single-line.
render_env() {
  bash -c '
    set -euo pipefail
    set -a; . "$1"; set +a
    sed -n "s/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p" "$1" | awk "!seen[\$0]++" \
      | while IFS= read -r key; do printf "%s=%s\n" "$key" "${!key-}"; done
  ' render "$ENV_FILE"
}

TARGET="all"
PUSH=1
for arg in "$@"; do
  case "$arg" in
    users|all) TARGET="$arg" ;;
    --no-push) PUSH=0 ;;
    *) echo "Usage: $0 [users] [--no-push]" >&2; exit 2 ;;
  esac
done

echo "==> Resolving secrets locally (pass/gpg run on this machine only)"
RENDERED_ENV="$(render_env)"

if ! grep -q '^CLOUDFLARE_TUNNEL_TOKEN=.\+' <<<"$RENDERED_ENV"; then
  echo "ERROR: CLOUDFLARE_TUNNEL_TOKEN resolved to nothing. Create the tunnel in" >&2
  echo "the Cloudflare Zero Trust dashboard and store its token in pass — nothing" >&2
  echo "else exposes the broker." >&2
  exit 1
fi
if ! grep -q '^MQTT_USERS=.\+' <<<"$RENDERED_ENV"; then
  echo "ERROR: MQTT_USERS resolved to nothing; the broker would have no accounts." >&2
  exit 1
fi

SSH=(ssh -i "$SSH_KEY" -p "$DEPLOY_PORT" "$DEPLOY_USER@$DEPLOY_HOST")
SECRETS_REMOTE="/dev/shm/chatnyto-mqtt.env" # tmpfs: gone on reboot, never on disk

if [ "$PUSH" = 1 ]; then
  echo "==> Pushing $(git rev-parse --abbrev-ref HEAD) -> $GIT_REMOTE/$DEPLOY_BRANCH"
  git push "$GIT_REMOTE" "HEAD:$DEPLOY_BRANCH"
fi

echo "==> Updating the checkout on $DEPLOY_HOST"
"${SSH[@]}" "set -e; cd '$DEPLOY_DIR' \
  && git fetch origin '$DEPLOY_BRANCH' \
  && git reset --hard 'origin/$DEPLOY_BRANCH'"

echo "==> Streaming secrets to tmpfs (never written to the server's disk)"
printf '%s\n' "$RENDERED_ENV" | "${SSH[@]}" "umask 177 && cat > '$SECRETS_REMOTE'"

echo "==> Deploying on the server (target: $TARGET)"
"${SSH[@]}" "cd '$DEPLOY_DIR' && status=0; \
  ENV_FILE='$SECRETS_REMOTE' ./deploy/deploy.sh '$TARGET' || status=\$?; \
  rm -f '$SECRETS_REMOTE'; exit \$status"

echo "==> Deployed."
echo "    In the app: Networks -> + -> Host: wss://<your domain>/mqtt"
echo "    with the username and password you put in MQTT_USERS."
