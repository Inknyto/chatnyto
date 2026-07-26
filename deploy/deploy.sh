#!/usr/bin/env bash
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
case "$TARGET" in all|users) ;; *)
  echo "Usage: $0 [users]  (no argument = deploy everything)" >&2; exit 2;;
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

echo "==> Writing broker accounts"
write_users
[ "$TARGET" = "users" ] && { "${COMPOSE[@]}" restart mqtt; exit 0; }

echo "==> Starting the broker and the tunnel"
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
