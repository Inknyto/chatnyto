# ChatNyto internals

A map of how the app is put together and how a message, a call and an
identity actually move through it.

Written once, on request, from the code as it stands. It is **not**
regenerated when the code changes — if it has drifted, ask for it to be
redone rather than trusting it.

- [1. The shape of the app](#1-the-shape-of-the-app)
- [2. What travels over MQTT](#2-what-travels-over-mqtt)
- [3. Sending a message](#3-sending-a-message)
- [4. Receiving a message](#4-receiving-a-message)
- [5. Keys, and where each one comes from](#5-keys-and-where-each-one-comes-from)
- [6. Accounts and identities](#6-accounts-and-identities)
- [7. A call, and the three roads its audio can take](#7-a-call-and-the-three-roads-its-audio-can-take)
- [8. Staying reachable when the app is closed](#8-staying-reachable-when-the-app-is-closed)
- [9. Joining a network](#9-joining-a-network)
- [10. What is stored, and where](#10-what-is-stored-and-where)
- [11. The server side](#11-the-server-side)
- [12. The AI side](#12-the-ai-side)

---

## 1. The shape of the app

Four ideas hold the whole thing up:

1. **A broker is a dumb pipe.** It sees ciphertext and topic names, nothing
   else. Any MQTT broker will do — a server, mosquitto on a laptop, the
   ESP32 in the LoRa box.
2. **An account is its key pair.** Not a row in a database somewhere. That
   one fact is what makes the same identity work on several devices, several
   identities work on one device, and deduplication trivial.
3. **Nothing needs configuring.** Presence announcements find people;
   published profiles find networks; the app asks the server, not the user.
4. **Offline is the normal case**, not an error state.

```mermaid
graph TB
    subgraph UI["Screens"]
        Shell["HomeShell<br/>chats · calls · people · updates · communities"]
        Chat["RevampChatPage"]
        CallUI["CallPage + CallBanner"]
        Nets["BrokersPage · NetworkGraphPage"]
        Acct["AccountPage · AccountsPage · ContactsPage"]
    end

    subgraph Domain["Domain services (singletons, ChangeNotifier)"]
        ChatSvc["ChatService<br/>chats, history, outbox, sync, receipts"]
        CallSvc["CallService<br/>call state machine"]
        Contacts["ContactBook<br/>people, local names"]
        Ident["IdentityService<br/>accounts, keys, scope"]
    end

    subgraph Media["Call media"]
        Ice["IceDirectory<br/>STUN/TURN from network profiles"]
        WebRTC["flutter_webrtc<br/>direct / relayed by TURN"]
        Relay["VoiceRelay<br/>8 kHz IMA ADPCM over MQTT"]
    end

    subgraph Transport["Transport"]
        Broker["BrokerService<br/>one MQTT client per network<br/>chunking · presence · discovery · heartbeat"]
        Dir["NetworkDirectory<br/>/.well-known/chatnyto.json"]
    end

    subgraph Platform["Platform edges"]
        Notif["NotificationService + Ringtones"]
        BgSvc["BackgroundService<br/>foreground service"]
        BgCli["BackgroundClient<br/>listens when the app is closed"]
        Store["SharedPreferences<br/>encrypted at rest"]
        Keystore["Secure storage<br/>Keystore · Keychain · libsecret · DPAPI"]
    end

    Shell --> ChatSvc
    Chat --> ChatSvc
    CallUI --> CallSvc
    Nets --> Broker
    Nets --> Dir
    Acct --> Ident
    Acct --> Contacts

    ChatSvc --> Broker
    ChatSvc --> Ident
    ChatSvc --> Notif
    CallSvc --> ChatSvc
    CallSvc --> Ice
    CallSvc --> WebRTC
    CallSvc --> Relay
    Relay --> ChatSvc
    Contacts --> Ident
    Dir --> Ice

    ChatSvc --> Store
    Ident --> Store
    Ident --> Keystore
    Broker --> Keystore
    BgSvc --> BgCli
    BgCli --> Broker
    BgCli --> ChatSvc
    BgCli --> Notif
```

Note the one-way arrows out of `Transport`: nothing below the line knows
about screens. `BrokerService` exposes two callbacks (`onChatMessage`,
`onHeartbeat`) and `ChatService` claims them — that is the only seam
between the wire and the app.

---

## 2. What travels over MQTT

Four topic families, and only two of them carry anything private.

| Topic | Retained | Payload | Encrypted |
|---|---|---|---|
| `chatnyto/presence/<fingerprint>` | yes | `PublicIdentity` JSON — name, both public keys, picture, self-signature | no (all public by definition, and signed) |
| `chatnyto/chat/dm/<fpA>--<fpB>` | no | AES-256-GCM envelope | yes, X25519 ECDH between the pair |
| `chatnyto/chat/group/<slug>` | no | AES-256-GCM envelope | yes, key derived from the passphrase or the topic |
| `chatnyto/groups/<slug>` | yes | public group advertisement | no |

The DM topic name is the two fingerprints sorted and joined, so both sides
compute the same one without agreeing on anything.

Every client subscribes to `chatnyto/chat/#`, which means **the broker
echoes your own publications back to you**. Several things in the code exist
only because of that; each is marked in place.

### Inside an envelope

```mermaid
graph LR
    subgraph Wire["On the wire"]
        Chunk["{chunk, i, n, d}<br/><i>only when over 2 KB</i>"]
        Env["{enc: aes-256-gcm, n, c, m}"]
    end
    subgraph Clear["After decryption"]
        Msg["message<br/>f · n · t · ts · d? · img?"]
        Sync["sync_req<br/>since"]
        Rcpt["receipt<br/>st · ts[] · from"]
        Call["call<br/>call: offer|answer|ice|relay|voice|decline|end<br/>from"]
        Ctrl["group_rename · group_delete · group_admins<br/>by · sig · ts"]
    end
    Chunk -->|reassembled| Env
    Env --> Msg
    Env --> Sync
    Env --> Rcpt
    Env --> Call
    Env --> Ctrl
```

Two things worth knowing about that picture:

- **The chunk wrapper is outside the encryption**, and has to be: the
  receiver must put the pieces back together before it has anything it can
  decrypt. It leaks only a length, which the packet sizes leaked anyway.
- **`type` is written last** when a call signal is assembled. The payload
  carries keys of its own — an SDP offer has a `type` too — and if it could
  overwrite the envelope's kind, the other side files a ring away as an
  unreadable chat message and the phone never rings. It did, once.

---

## 3. Sending a message

```mermaid
sequenceDiagram
    participant U as User
    participant P as RevampChatPage
    participant C as ChatService
    participant B as BrokerService
    participant M as Broker(s)

    U->>P: types, taps send
    P->>C: sendText(chat, text, image?)
    C->>C: _keyFor(chat) — cached
    C->>C: build RevampMessage(ts = now)
    C->>C: _append() — shown immediately, stored encrypted

    alt a broker is connected
        C->>C: status = sent
        C->>B: publishToAll(topic, envelope)
        alt envelope over 2 KB
            B->>M: {chunk, 0, n, …}
            B->>M: … 12 ms apart …
            B->>M: {chunk, n-1, n, …}
        else
            B->>M: envelope
        end
    else nothing connected
        C->>C: status = pending (clock icon)
        C->>C: outbox, encrypted at rest
    end

    Note over C,M: later, on connect or heartbeat
    C->>B: _flushOutbox() → publish, status = sent
```

The message appears in the conversation **before** anything is published,
and is stored whether or not it can be sent. Offline is not a failure here;
it is the same path with one branch taken differently.

---

## 4. Receiving a message

```mermaid
sequenceDiagram
    participant M as Broker
    participant B as BrokerService
    participant C as ChatService
    participant N as NotificationService

    M->>B: publication on chatnyto/chat/#
    opt a piece of a larger message
        B->>B: _collectChunk — hold until the last one
    end
    B->>C: onChatMessage(topic, payload)
    C->>C: match topic to a chat
    opt unknown DM addressed to us
        C->>C: startDm(peer) — created on the fly
    end
    C->>C: decrypt with the channel key
    alt sync_req
        C->>C: _replayHistory(since) — throttled, 2 min per chat
    else receipt
        C->>C: move our own messages to delivered / read
    else call
        C->>C: onCallSignal → CallService
    else group control
        C->>C: verify Ed25519 signature, then apply
    else a message
        C->>C: from == me? store quietly and stop
        C->>C: _append — deduped on (ts, from)
        C->>C: _acknowledge — batched receipt, 600 ms
        C->>N: showMessage unless that chat is on screen
    end
```

Two details that are easy to miss:

- **Dedup is `(ts, from)`.** That is what makes the broker's echo, a replay
  from the sync protocol, and a genuine resend all harmless.
- **Receipts are batched.** Catching up after a day offline delivers a whole
  conversation at once, and a separate publish per message would answer a
  burst with a burst.

### The sync protocol

There is no server holding history, so the clients hold it for each other.

```mermaid
sequenceDiagram
    participant A as Device A (was offline)
    participant M as Broker
    participant B as Device B
    participant D as Device D

    A->>M: sync_req {since: newest ts I hold}
    M->>B: sync_req
    M->>D: sync_req
    Note over B,D: each waits 0–3 s at random,<br/>so they do not all answer at once
    B->>M: the messages after `since`, 20 ms apart
    M->>A: …
    Note over D: within 2 min of its last replay<br/>for this chat → stays quiet
```

---

## 5. Keys, and where each one comes from

```mermaid
graph TB
    Pw["Password<br/><i>typed, never stored in app storage</i>"]
    Rec["Recovery code<br/>120 random bits, shown once"]

    Pw -->|PBKDF2-HMAC-SHA256, 210k| VaultK["vault key"]
    Rec -->|PBKDF2-HMAC-SHA256, 20k| RecK["recovery key"]
    VaultK -->|AES-256-GCM| Seeds
    RecK -->|AES-256-GCM| Seeds

    Seeds["Private seeds<br/>x25519 + ed25519"]
    Seeds --> X["X25519 key pair"]
    Seeds --> Ed["Ed25519 key pair"]

    X -->|"ECDH with a peer,<br/>then HKDF 'chatnyto:p2p'"| DmK["DM channel key"]
    X -->|"HKDF 'chatnyto:storage'"| StoreK["at-rest key<br/>history + outbox"]
    Ed -->|signs| Presence["presence advertisement"]
    Ed -->|signs| GroupCtrl["group rename / delete / admins"]

    Topic["group passphrase,<br/>or the topic when there is none"]
    Topic -->|"PBKDF2 60k, salt 'chatnyto:'+topic"| GroupK["group channel key"]

    DmK --> Envelope["AES-256-GCM envelope"]
    GroupK --> Envelope
```

Consequences that fall straight out of this shape:

- **A broker operator can read nothing.** They hold no key material at all.
- **Forgetting the password loses everything** unless the recovery code was
  kept. That is a property of the design, not an oversight — anything that
  let the app reopen an account without either secret would be a back door.
- **A public group is only private from the broker**, not from anyone who
  knows its name: the key comes from the topic. A passphrase is what makes a
  group actually private.
- **Two devices holding the same account derive the same at-rest key**, so
  each can read what it stored itself. History is not synchronised by
  copying files; it is replayed over the sync protocol.

---

## 6. Accounts and identities

```mermaid
graph LR
    subgraph Device["One device"]
        A1["StoredAccount<br/>id = X25519 public key<br/>vault + recovery blob"]
        A2["StoredAccount<br/>another identity"]
        Active["accounts.active"]
    end

    A1 -->|"scope = ''<br/>(the first account keeps<br/>the unsuffixed keys)"| S1["revamp.chats.v1<br/>contacts.v1<br/>calls.history.v1<br/>profile.*"]
    A2 -->|"scope = '.' + short hash"| S2["revamp.chats.v1.ab12cd34<br/>contacts.v1.ab12cd34<br/>…"]

    Active --> A1
```

The account **id is the X25519 public key**, which is why importing an
account the device already holds refreshes it instead of duplicating it, and
why the same identity on three devices is one account rather than three.

Storage is separated by a `scope` suffix. The first account on a device gets
the empty scope so that a device which only ever has one account keeps the
simple layout — and so the migration from the single-identity build moved no
data at all.

Switching identity has to drop the **in-memory** copies as well as pointing
at different keys; that is what `forgetAccountState()` is for. Getting only
half of that right is why a second identity used to show the first one's
chats until the app was restarted.

```mermaid
stateDiagram-v2
    [*] --> NoAccount
    NoAccount --> Unlocked: create(name, password)<br/>recovery code shown once
    Unlocked --> Locked: lock() · switchTo(other)
    Locked --> Unlocked: unlock(password)
    Locked --> Unlocked: unlockWithRecoveryCode(code)
    Unlocked --> Unlocked: changePassword — reseals the same seeds
    Unlocked --> [*]: deleteAccount — scoped keys erased
    note right of Locked
        Stored chats are encrypted under a key
        derived from this account's own seed,
        so "locked" is not a UI state — the
        data is genuinely unreadable.
    end note
```

---

## 7. A call, and the three roads its audio can take

Signalling always goes over MQTT, inside the pair's own encrypted channel.
Only the audio has choices.

```mermaid
sequenceDiagram
    participant A as Caller
    participant M as Broker
    participant B as Callee

    A->>A: getUserMedia, createOffer
    A->>M: call:offer (repeated every 2 s while ringing)
    M->>B: call:offer
    B->>B: ring — full screen, insistent, vibrating
    B->>M: call:answer
    M->>A: call:answer
    A-->>M: call:ice ⇄ (loopback candidates dropped)
    M-->>B: …

    alt a direct route exists
        A->>B: SRTP, peer to peer
    else within 8 seconds it does not
        A->>M: call:relay
        M->>B: call:relay
        Note over A,B: both tear WebRTC down and switch
        A->>M: call:voice {f: ADPCM frame} every 60 ms
        M->>B: …
        B->>M: call:voice
        M->>A: …
    end
```

```mermaid
graph TB
    Start["Answered"] --> Direct{"Direct route<br/>within 8 s?"}
    Direct -->|"same WiFi / LoRa AP —<br/>host candidates"| Best["Peer to peer<br/><i>best: lowest latency,<br/>platform AEC, adaptive</i>"]
    Direct -->|"mobile data, if the network<br/>published STUN/TURN"| Turn["Via STUN/TURN<br/><i>good</i>"]
    Direct -->|"nothing worked"| Relayed["ADPCM over MQTT<br/><i>narrow but it goes through</i>"]

    Relayed --> Note["8 kHz mono · 4 bits/sample · 60 ms frames<br/>~4 kB/s of audio, ~8 kB/s encrypted<br/>each frame carries its own predictor state,<br/>so a lost frame costs 60 ms and nothing more"]
```

Why each piece is there:

- **The repeated offer** costs nothing (signalling is tiny) and buys two
  things: a lost packet no longer kills the call, and a phone whose app was
  closed can be woken by the ring and still find the call waiting.
- **STUN is not optional over mobile data.** With none at all, a phone
  behind carrier NAT never learns an address the other side could dial, so
  the call can *never* connect — it just says "Connecting…" forever. That
  was the bug.
- **Loopback ICE candidates are filtered.** They can never reach another
  device, but ICE still pairs and times out on them. Removing them took a
  measured 32 seconds down to 0.4.
- **The relay is Android and iOS only.** Raw capture and playback have no
  Linux build, so a desktop has the first two roads and not the third.

---

## 8. Staying reachable when the app is closed

The hardest part of the whole app, because it is really a question about
Android rather than about ChatNyto.

```mermaid
graph TB
    subgraph P["The app's process"]
        Main["Main isolate<br/>the whole app"]
        Task["Service isolate<br/>BackgroundClient"]
    end
    FgSvc["Foreground service<br/>'ChatNyto is connected'"]

    FgSvc -->|holds the process open| P
    Main -->|"stamps runtime.uiAlive<br/>every 10 s"| Pref[("SharedPreferences")]
    Task -->|"reads it every 15 s"| Pref

    Task -->|"stamp older than 40 s<br/>⇒ the app is gone"| Take["connect · listen · ring"]
    Task -->|"stamp fresh<br/>⇒ the app is back"| Stand["disconnect · lock · stand down"]
```

Only one isolate is ever the client, because two would notify everything
twice and — worse — write the same preferences file at the same time.

The service isolate is deliberately **less** than the app:

| | App | Service isolate |
|---|---|---|
| Connects to brokers | yes | yes, when the app is gone |
| Decrypts what arrives | yes | yes |
| Raises notifications | yes | yes |
| **Stores messages** | yes | **no** |
| **Answers calls** | yes | **no** |

Both "no"s are on purpose:

- **It writes nothing.** Losing history to two isolates racing on one file
  would be a far worse bug than the one being fixed, and the cost is small:
  when the app opens, `sync_req` asks the other side to replay what was
  missed. That protocol already exists for exactly this.
- **It does not answer.** Answering needs a microphone, a screen, and the
  call machinery. Instead it rings with a full-screen intent, which brings
  the app up — and because the caller repeats its offer, the app arrives to
  find the call still waiting.

```mermaid
sequenceDiagram
    participant C as Caller
    participant M as Broker
    participant S as Service isolate
    participant A as The app
    participant U as User

    Note over A: closed; process restarted by the service
    C->>M: call:offer
    M->>S: call:offer
    S->>S: decrypt, recognise a ring
    S->>U: full-screen notification + ringtone<br/><i>no Answer button — it could not honour one</i>
    U->>A: taps, or the full-screen intent opens it
    A->>A: unlock, connect, stamp runtime.uiAlive
    C->>M: call:offer (still repeating)
    M->>A: call:offer
    A->>U: the real call screen, Answer / Decline
    S->>S: next tick: stamp is fresh → stands down
```

There is one more layer, and it is not code: **manufacturer battery
saving**. A foreground service is supposed to keep a process alive and on
stock Android it does; OEM layers will close it anyway. That is why the
settings page offers the battery exemption, and why it only appears when the
phone has not granted it.

---

## 9. Joining a network

The user should only ever type the address they already know.

```mermaid
sequenceDiagram
    participant U as User
    participant App as BrokersPage
    participant W as https://host/.well-known/chatnyto.json
    participant K as Device keystore
    participant M as Broker

    U->>App: "supa-tech.com" — or scans a code, or pastes a link
    App->>W: GET, 6 s timeout
    alt the server publishes a profile
        W-->>App: {name, url, port, username, password, ice[]}
        App->>K: store the sign-in
        App->>App: remember the STUN/TURN servers for calls
    else nothing published (a LAN or LoRa broker)
        Note over App: use the address exactly as typed
    end
    App->>M: connect (wss / mqtts / mqtt)
```

This is why the Add-network dialog has no password field. The credential
goes from HTTPS straight into the platform keystore; it is never displayed,
never typed, and never written to the app's own preferences.

It is also what makes a QR code safe to show to a room: the code carries the
address alone, and the other person's app fetches its own sign-in. Including
the credential in the code is still possible, but it is a deliberate switch.

---

## 10. What is stored, and where

```mermaid
graph LR
    subgraph SP["SharedPreferences — plain"]
        B1["brokers.v1<br/><i>addresses only, never credentials</i>"]
        B2["accounts.v2<br/><i>public keys clear, seeds sealed</i>"]
        B3["contacts.v1&lt;scope&gt;<br/>+ .alias"]
        B4["calls.history.v1&lt;scope&gt;"]
        B5["profile.picture&lt;scope&gt;"]
        B6["calls.ice.v1 · ringtone.* · settings"]
    end
    subgraph SPE["SharedPreferences — AES-256-GCM at rest"]
        E1["revamp.msgs.enc&lt;scope&gt;.&lt;chatId&gt;"]
        E2["revamp.outbox.enc&lt;scope&gt;"]
    end
    subgraph KS["Platform secure storage"]
        K1["identity.password"]
        K2["broker.credentials.&lt;network&gt;"]
    end
    subgraph FS["App files"]
        F1["ringtones/call.* · message.*"]
    end

    StoreK["at-rest key<br/>HKDF of the identity seed"] --> E1
    StoreK --> E2
```

The rule the layout follows: **anything that would let somebody else in
lives in the platform keystore, never in the app's own preferences** — so a
data backup extracted off the device reveals no password and no broker
credential. Message history is encrypted under a key derived from the
identity seed, so it is unreadable without unlocking the account, and each
account's history is unreadable by the others by construction rather than by
a check that could be forgotten.

---

## 11. The server side

Optional. Two people on one WiFi never touch any of it.

```mermaid
graph TB
    subgraph Server["A VPS, behind a Cloudflare tunnel"]
        Mq["mosquitto<br/>authenticated, restricted to chatnyto/#<br/>MQTT + MQTT-over-WebSockets"]
        Prof["nginx<br/>serves /.well-known/chatnyto.json"]
        Tun["cloudflared"]
        Turn["coturn<br/><i>optional, profile: turn</i>"]
    end
    App["ChatNyto"]

    App -->|"wss://host/mqtt"| Tun --> Mq
    App -->|"https://host/.well-known/…"| Tun --> Prof
    App -->|"turn:host:3478 — UDP,<br/>cannot use the tunnel"| Turn
```

The tunnel means no port is opened for the broker at all. coturn is the one
exception — TURN is UDP and an HTTP tunnel carries no UDP — which is why it
is opt-in and needs `3478/udp`, `3478/tcp` and `49160-49200/udp` open.

`deploy/.env.prod` is the single source of truth for accounts; the password
file is rebuilt from it, so removing somebody from that variable removes
their access.

---

## 12. The AI side

A separate subsystem that shares nothing with the messaging path except the
screens it is reached from. Bring-your-own-key throughout: no ChatNyto
service sits in the middle.

```mermaid
graph LR
    Page["AiChatPage"] --> Client["AiClient"]
    Client --> Prov{"AiProtocol"}
    Prov -->|openAiCompatible| P1["OpenAI-shaped /chat/completions<br/><i>incl. local Ollama, LM Studio</i>"]
    Prov -->|anthropic| P2["Anthropic Messages API"]
    Prov -->|gemini| P3["Gemini generateContent"]
    Client --> Mcp["McpClient<br/>JSON-RPC over HTTP or SSE"]
    Mcp --> Tools["tools/list · tools/call"]
    Config["AiConfig<br/>agents · providers · MCP servers"] --> Client
```

Worth noting: an agent can be pointed at a model running on the same
network, which keeps the whole conversation inside it — the same instinct as
the rest of the app.
