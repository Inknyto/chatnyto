# Running a ChatNyto broker on a server

ChatNyto normally needs no server at all: phones find each other through the
Heltec LoRa box or a broker on the same WiFi. A public broker is for the case
where people are not on the same network — it relays the same end-to-end
encrypted traffic, and can read none of it.

## What this deploys

| Piece | What it does |
| --- | --- |
| `mosquitto` | The MQTT broker. Authenticated users only, restricted to the `chatnyto/#` topic tree. |
| `cloudflared` | Publishes the broker as `wss://<your domain>/mqtt` through a Cloudflare tunnel, so no port is opened on the server. |

A plain MQTT port cannot travel through an HTTP tunnel, which is why the
broker also listens for MQTT over WebSockets — the app speaks both, and picks
the right one from the URL scheme.

## One-time setup

1. **On the server**, clone the repo where `DEPLOY_DIR` points:
   ```bash
   sudo mkdir -p /opt/chatnyto && sudo chown "$USER" /opt/chatnyto
   git clone <repo> /opt/chatnyto
   ```
   Docker and the Compose plugin must be installed.

2. **In Cloudflare Zero Trust**, create a tunnel and add a public hostname
   route for your domain with path `/mqtt` pointing at `http://mqtt:9001`.
   Copy the tunnel token.

3. **On your machine**, fill in the two config files:
   ```bash
   cp deploy/deploy.conf.example deploy/deploy.conf     # server address
   cp deploy/.env.prod.example  deploy/.env.prod        # accounts + token
   ```
   `.env.prod` entries may be `$(pass show …)`; they are resolved on your
   machine and streamed to the server's tmpfs, so secrets never touch its
   disk and are never committed.

## Deploying

```bash
./deploy/deploy-remote.sh            # push the branch and deploy
./deploy/deploy-remote.sh --no-push  # deploy what is already on the branch
./deploy/deploy-remote.sh users      # only rewrite the broker accounts
```

## Connecting the app

In ChatNyto: **Networks → + →**

| Field | Value |
| --- | --- |
| Name | anything, e.g. "Internet" |
| Host | `wss://<your domain>/mqtt` |
| Port | leave 1883; the URL's scheme decides (443 for `wss`) |
| Username / Password | one of the `MQTT_USERS` pairs |

Or share it by QR code from the network's long-press menu — the code carries
the address and credentials, so the other person scans it and is connected.

## Adding or removing people

Edit `MQTT_USERS` in `deploy/.env.prod`, then:

```bash
./deploy/deploy-remote.sh users
```

The password file is rebuilt from that variable, so it is the single source
of truth and removing someone from it removes their access.

## What the server can and cannot see

It relays ciphertext: message contents, group names and identities are
encrypted end-to-end, and the broker holds no keys. It does see the metadata
any relay sees — which accounts connect, when, and which topics they use.
Connection logging is turned off in `mosquitto.conf` to keep as little of
that as possible. For conversations where even metadata matters, use the LoRa
box or a broker on your own network instead.
