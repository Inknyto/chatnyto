#!/usr/bin/env bash
# ~/Documents/git/chatnyto/deploy/deploy.sh 28 Jul 2026 at 10:06:21 PM
# Brings up the ChatNyto MQTT broker on the server.
#
# Runs ON the server (deploy-remote.sh calls it over SSH). It expects an env
# file with the real secrets — deploy/.env.prod by default, or ENV_FILE
# pointing elsewhere (deploy-remote.sh streams them to tmpfs so they never
# rest on the server's disk).
#
#   ./deploy/deploy.sh          # start or update the stack
#   ./deploy/deploy.sh users    # (re)write the password file from MQTT_USERS
set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="${1:-all}"
case "$TARGET" in all|users|profile) ;; *)
  echo "Usage: $0 [users|profile]  (no argument = deploy everything)" >&2; exit 2;;
esac

ENV_FILE="${ENV_FILE:-deploy/.env.prod}"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found. Copy deploy/.env.prod.example and fill it in." >&2
  exit 1
fi

COMPOSE=(docker compose --env-file "$ENV_FILE" -f deploy/docker-compose.yml)

# --- accounts ----------------------------------------------------------------
# MQTT_USERS is a space-separated list of user:password pairs. The password
# file is rebuilt from it, so the env file stays the single source of truth
# and no credentials are committed.
write_users() {
  # shellcheck disable=SC1090
  set -a; . "$ENV_FILE"; set +a
  : "${MQTT_USERS:?Set MQTT_USERS in $ENV_FILE (user:password pairs)}"

  local passwd="deploy/mosquitto/config/passwd"
  : > "$passwd"
  chmod 600 "$passwd"
  for pair in $MQTT_USERS; do
    local user="${pair%%:*}"
    local pass="${pair#*:}"
    if [ -z "$user" ] || [ -z "$pass" ] || [ "$user" = "$pair" ]; then
      echo "ERROR: MQTT_USERS entries must look like user:password" >&2
      exit 1
    fi
    docker run --rm -v "$PWD/deploy/mosquitto/config:/c" eclipse-mosquitto:2.0 \
      mosquitto_passwd -b /c/passwd "$user" "$pass"
  done
  echo "==> Wrote $(grep -c : "$passwd") account(s) to $passwd"
}

# --- published profile -------------------------------------------------------
# The app should only ever need the address the user already knows. This file
# answers for the server: where its broker is, and which account to use. It is
# fetched over HTTPS and the credential goes straight into the device
# keystore, so it is never typed and never displayed.
write_profile() {
  # shellcheck disable=SC1090
  set -a; . "$ENV_FILE"; set +a
  : "${PUBLIC_HOST:?Set PUBLIC_HOST in $ENV_FILE (e.g. supa-tech.com)}"
  : "${APP_USER:?Set APP_USER in $ENV_FILE (an account from MQTT_USERS)}"
  : "${APP_PASSWORD:?Set APP_PASSWORD in $ENV_FILE}"

  # The call servers, when this deployment runs one. Without them two people
  # on mobile data can message each other but not call: neither phone has an
  # address the other can reach. Published here rather than built into the
  # app, so the app keeps needing nothing but the domain.
  local ice="[]"
  if [ -n "${TURN_USER:-}" ] && [ -n "${TURN_PASSWORD:-}" ]; then
    ice=$(cat <<ICE
[
    {"urls": "stun:${PUBLIC_HOST}:3478"},
    {"urls": "turn:${PUBLIC_HOST}:3478?transport=udp",
     "username": "${TURN_USER}", "credential": "${TURN_PASSWORD}"},
    {"urls": "turn:${PUBLIC_HOST}:3478?transport=tcp",
     "username": "${TURN_USER}", "credential": "${TURN_PASSWORD}"}
  ]
ICE
    )
  fi

  mkdir -p deploy/wellknown
  local out="deploy/wellknown/chatnyto.json"
  cat > "$out" <<JSON
{
  "name": "${PUBLIC_NAME:-$PUBLIC_HOST}",
  "url": "wss://${PUBLIC_HOST}/mqtt",
  "username": "${APP_USER}",
  "password": "${APP_PASSWORD}",
  "ice": ${ice}
}
JSON
  chmod 644 "$out"
  echo "==> Wrote $out (wss://${PUBLIC_HOST}/mqtt as ${APP_USER})"
  [ "$ice" = "[]" ] || echo "==> Published turn:${PUBLIC_HOST}:3478 for calls"
}

echo "==> Writing broker accounts"
write_users
echo "==> Writing the published profile"
write_profile
[ "$TARGET" = "profile" ] && { "${COMPOSE[@]}" up -d profile; exit 0; }
[ "$TARGET" = "users" ] && { "${COMPOSE[@]}" restart mqtt; exit 0; }

echo "==> Starting the broker and the tunnel"
# The TURN server only joins in when the env file asks for it — it is the one
# piece that needs open ports rather than the tunnel.
if [ -n "${TURN_USER:-}" ] && [ -n "${TURN_PASSWORD:-}" ]; then
  : "${TURN_PUBLIC_IP:?Set TURN_PUBLIC_IP in $ENV_FILE (the server\'s public IP)}"
  COMPOSE+=(--profile turn)
fi
"${COMPOSE[@]}" up -d --remove-orphans

echo "==> Waiting for the broker to answer"
for _ in $(seq 1 30); do
  if "${COMPOSE[@]}" ps --status running mqtt | grep -q mqtt; then
    if "${COMPOSE[@]}" exec -T mqtt mosquitto_sub -h localhost -p 1883 \
        -t '$SYS/broker/uptime' -C 1 \
        -u "${MQTT_HEALTH_USER}" -P "${MQTT_HEALTH_PASSWORD}" >/dev/null 2>&1; then
      echo "==> Broker healthy."
      exit 0
    fi
  fi
  sleep 2
done

echo "WARNING: the broker did not answer in time; check 'docker compose logs mqtt'." >&2
exit 1
