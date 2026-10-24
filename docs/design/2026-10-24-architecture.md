# Chama — Architecture

Status: accepted · 2026-10-24

Chama is a free, open-source messenger for Brazil with the features and feel of WhatsApp:
one app for Android, iOS, desktop and the web (in the style of WhatsApp Web), built from a
single codebase. Android ships first. It is built to be run by a
public, non-profit operator (possibly a public body) without that operator being able to
read messages, rank content or silently censor users.

## 1. Goals and non-goals

**Goals**

- WhatsApp feature parity, delivered in milestones (section 7).
- End-to-end encryption (E2EE) on by default for every chat, group and status.
- Sign-up with a phone number and SMS code, like WhatsApp.
- One cross-platform app (Android first; web, iOS and desktop from the same code), so
  contributors work in one codebase.
- No ranking, no feed algorithm, no ads. Chats show in time order only.
- Everything runs locally with one command for development.
- An open protocol, so other operators (universities, states, NGOs) can run compatible
  servers later (federation).

**Non-goals (for now)**

- iOS and desktop release builds in the MVP. The code supports them; store releases come
  after Android.
- Payments.
- Business API.
- Interop with WhatsApp itself.

## 2. Key decision: build on Matrix

Chama uses the [Matrix](https://spec.matrix.org) open protocol, with our own clients.

| Option | Verdict |
|---|---|
| **Matrix protocol + own WhatsApp-style clients** | **Chosen.** Audited E2EE (vodozemac) on every platform, including the browser; mature server; federation built in. Already the base of government messengers (France: Tchap; Germany: BwMessenger). |
| Fork Signal (server + Android) | Best crypto, but the server is hard to self-host, there is no browser client, and forks are discouraged. |
| Own protocol + libsignal | Full control, but we would re-build multi-device, groups and sync, and libsignal has no browser build. Highest security risk. |
| XMPP (ejabberd + Conversations) | Proven (early WhatsApp ran on ejabberd), but weak browser E2EE and a fragmented feature set. |
| Fork Element apps and re-skin | Fastest parity, but huge codebases whose UX fights the WhatsApp model. |

Writing our own clients on the official Matrix SDKs gives us full control of the UX while
the hard parts (crypto, sync, multi-device) come from audited libraries.

## 3. System overview

```
 Chama app (Flutter): Android · Web · iOS · desktop
   famedly matrix Dart SDK + vodozemac (native on mobile/desktop, wasm on web)
                              │  HTTPS
                              ▼
   ┌───────────────────────────── reverse proxy (Caddy) ─────────────────────────────┐
   │   /_matrix/*  → Synapse (homeserver)          /id/* → chama-id                  │
   └─────────────────────────────────────────────────────────────────────────────────┘
            │                                     │
       PostgreSQL                           SQLite (OTP codes, link sessions)
            │
   later: LiveKit (calls), Sygnal/UnifiedPush (push), Coturn (TURN)
```

### Components

| Unit | What it does | Depends on |
|---|---|---|
| `server/` | Docker Compose stack: Synapse (main + workers), PostgreSQL, Redis, Caddy, chama-id. Config templates and a seed script. | Docker |
| `services/chama-id/` | Phone sign-in (SMS code → signed JWT), contact discovery, device-link rendezvous. Small TypeScript service on Node 26. | Synapse admin API, SQLite |
| `app/` | The Chama app (Flutter) for every platform. Android layout on phones, WhatsApp-Web-style two-pane layout on wide screens. | `matrix` Dart SDK, `flutter_vodozemac` |
| `docs/` | Design and operator docs. | — |

Pinned starting versions (checked 2026-10-24): Synapse v1.163.2, Flutter 3.47 (stable),
`matrix` (Dart) 14.2.0, `flutter_vodozemac` 0.9.0. `matrix-js-sdk` 44.0.0 is used only by
Node test tools.

## 4. Identity and sign-in

- A Chama account is a Matrix user with an **opaque, random** ID, for example
  `@u7k3m9q2x4w8a1b5:chama.chat` (`u` + 16 lowercase base32 characters). The phone number
  is how you sign in and how contacts find you, but it is **not** part of the Matrix ID.
  chama-id keeps the mapping `phone → current account`.
- Why opaque IDs: Brazilian carriers give a cancelled number to a new customer after about
  180 days. If the number were the ID, the new owner would inherit the old owner's groups
  and chats and could post as them. Opaque IDs also keep phone numbers out of room state
  and out of federation.
- **Recycled numbers:** when a phone signs in and its current account has had no active
  device for 45 days, chama-id deactivates that account (contacts see "left") and creates
  a fresh one. Within 45 days the same account is used; the new device still has to be
  verified (section 5).
- Sign-in flow:
  1. Client → `POST /id/v1/otp/request {phone}`. chama-id stores a hashed 6-digit code
     (5 min TTL, max 5 tries, rate-limited per number and per IP, daily caps per number:
     5 codes and 10 wrong tries) and sends the SMS.
     In development the SMS provider is a stub: the code is printed in the chama-id log
     and the fixed code `000000` is accepted when `CHAMA_DEV=1`.
  2. Client → `POST /id/v1/otp/verify {phone, code}` → chama-id finds or creates the
     account and returns a JWT (HS256, 2 min TTL, `sub` = the opaque localpart,
     `iss`/`aud` checked) plus the `user_id`.
  3. Client → Matrix `POST /_matrix/client/v3/login` with type `org.matrix.login.jwt`.
     Synapse creates the account on first login (`create_non_existent_users=True`).
- Password registration on Synapse is disabled. Only chama-id can mint logins.
- **No password means no Matrix "user-interactive auth" (UIA).** Synapse offers UIA only
  for passwords and SSO, so actions that need it are done by chama-id through the Synapse
  admin API, after a fresh SMS code and a valid access token:
  - reset encryption identity, for a new phone without the recovery key (M2). The phone
    makes the new cross-signing keys and sends only the **public** signed key bundle;
    chama-id checks the SMS code, logs out the other devices and uploads the bundle as
    the user through a Matrix application service registration (`url: null`, so Synapse
    pushes no events to chama-id). Private keys never leave the phone. (Synapse honours
    "replace without UIA" only with MAS; the application-service route works without it.
    Moving sign-in to MAS is an option for M4.)
  - remove a linked device and deactivate the account (M4).
  chama-id talks to the admin API on the internal network only; the proxy blocks
  `/_synapse/admin` from outside.
- Dev mode (`CHAMA_DEV=1`, code `000000`) is refused unless `SERVER_NAME` ends in `.test`
  or `.localhost`, so it can never be switched on in production by mistake.
- Phone numbers are validated and normalised to E.164 (`libphonenumber-js` on the server).
- Profile: display name and avatar are Matrix profile fields. "Recado" (WhatsApp "about")
  uses an extended profile field (MSC4133); if the server lacks it, it is stored as state
  in the user's status room (section 6).

**Privacy:** phone numbers are not in Matrix IDs. A client shows a contact's saved name
(from the address book) or their display name. Showing the number to group members is an
app-level choice, as in WhatsApp.

## 5. Encryption, devices and linking

- All rooms are created with `m.room.encryption` (megolm). No unencrypted chats.
- Cross-signing is set up on first sign-in. A recovery key (secure backup, SSSS) is
  offered, as WhatsApp does with "end-to-end encrypted backup".
- **Security invariant: keys are only shared with verified devices.** The client uses the
  SDK setting `ShareKeysWith.crossVerifiedIfEnabled` (never `all`). A device that signs in
  with only an SMS code receives no message keys until it is verified by another device
  of the same user (QR or emoji) or with the recovery key. This is what stops SIM-swap
  attackers and the operator from reading new messages by signing in as someone.
- A user with no other device and no recovery key can **reset their identity** (new
  cross-signing keys, via chama-id, section 4). A reset **logs out every other device**
  of that account, so a SIM-swap attacker cannot stay hidden next to the real owner, who
  notices at once (as with WhatsApp re-registration). Contacts then see "Security code
  changed". Old messages stay unreadable on the new phone. From M4 the account PIN also
  gates resets.
- **Linking the web client (WhatsApp "Linked devices"):**
  1. Web generates an ephemeral X25519 key pair and opens a rendezvous at chama-id
     (`POST /id/v1/link` → `{id}`). It shows a QR code with `{id, pubkey, server}`.
  2. The phone scans it, asks Synapse for a one-time login token
     (`POST /_matrix/client/v1/login/get_token`), encrypts it to the web's public key and
     posts it to the rendezvous.
  3. Web polls, decrypts, logs in with `m.login.token`, and the phone verifies the new
     device and shares the cross-signing secrets and key-backup key over Matrix secret
     sharing. The new device can then read history.
  4. chama-id only ever sees ciphertext. Rendezvous entries expire after 2 minutes.
- Web can also sign in directly with phone + SMS code (fallback when no phone app exists).

## 6. Feature mapping (WhatsApp → Matrix)

| WhatsApp | Chama on Matrix |
|---|---|
| 1:1 chat | Encrypted room, `is_direct`, recorded in `m.direct` |
| Group | Encrypted room; admins = power level 100 |
| Text, emoji, links | `m.room.message` `m.text` (+ formatted body) |
| Reply / quote | `m.relates_to.m.in_reply_to` |
| Reaction | `m.reaction` (`m.annotation`) |
| Edit | `m.replace` relation |
| Delete for everyone | Redaction |
| Delete for me | Hidden locally (account data list) |
| Forward | Re-send content, marked forwarded (`chat.chama.forwarded`) |
| Photo, video, document | Encrypted attachments (`m.image`, `m.video`, `m.file`) |
| Voice note | `m.audio` + `org.matrix.msc3245.voice` + waveform |
| Sticker | `m.sticker` |
| Location | `m.location` (MSC3488) |
| Poll | Polls (MSC3381) |
| Contact card | `m.file` vCard |
| Ticks ✓ sent | Server accepted the event (has event ID) |
| Ticks ✓✓ delivered | To-device `chat.chama.delivered` from recipient devices (batched). Only in DMs and groups up to 32 members; larger groups show ✓ sent and blue ✓✓ read only |
| Ticks ✓✓ blue read | `m.read` receipt; private `m.read.private` if the user turns read receipts off |
| Typing… / recording… | `m.typing`; recording sent as typing plus `chat.chama.activity` |
| Online / last seen | Matrix presence, with a privacy switch |
| Starred messages | Account data `chat.chama.starred` |
| Pin / archive / mute chat | Room tags `m.favourite`-style (`chat.chama.pinned`, `chat.chama.archived`) and push rules |
| Disappearing messages | `m.room.retention` (Synapse purge) + client hides expired events |
| Block | `m.ignored_user_list` |
| Status (stories) | One room per user, custom type `chat.chama.status`, members = contacts; items expire after 24 h |
| Channels | Public room where only admins post (power levels); followers see only admins |
| Communities | Matrix Spaces holding groups and an announcement room |
| Broadcast list | Client-side list; sends a copy to each 1:1 room |
| Contacts | The phone app reads the address book, normalises to E.164, asks chama-id `POST /id/v1/directory/lookup` with SHA-256 hashes; chama-id answers which are registered and their current Matrix IDs. Lookups need an access token |
| Voice / video calls | MatrixRTC + LiveKit SFU (milestone M6) |
| Push notifications | Sygnal push gateway with UnifiedPush (ntfy) first, FCM optional (M7) |
| Report | Matrix `/report` to the operator's moderation queue |

Neutrality rules built into the product: chat list ordered by last activity only; channels
have no recommendation ranking; the directory is search-only (exact phone or channel name).

## 7. Milestones

The MVP (M1–M3 plus push) is the one-week target. It must be ready for millions of sign-ups
(section 12).

| # | Milestone | Done when |
|---|---|---|
| M1 | **Foundation.** Monorepo, Compose stack (Synapse with workers, Postgres, Redis, Caddy, chama-id), seed script. | `make up` starts the stack; a script signs two test users in with SMS code `000000` and they exchange an encrypted message. |
| M2 | **App core (Android first, also runs on web).** Phone sign-in, recovery key, device verification (QR/emoji) and identity reset, chat list, 1:1 and groups, text, replies, reactions, edit, delete, ticks, typing, presence, photos/files, voice notes, search, pin/archive/mute, unread counts, pt-BR UI, light and dark. | Integration test on Chrome and on the Android emulator: the app user chats with a test peer, sees ticks turn blue, sends a photo and a voice note. |
| M3 | **Android launch.** Contacts sync. Push: Sygnal gateway, FCM for Play Store builds, UnifiedPush (ntfy) for F-Droid and local testing. Release build, ABI splits. | Emulator test: Android user chats with a web user both ways; a message arrives as a notification with the app in the background. |
| M4 | **Link device and account safety.** QR linking (section 5), device list and removal, account PIN (two-step verification, also blocks re-registration of a number for 7 days), "new device" warnings to contacts. | Web linked by scanning its QR on the emulator reads earlier history. |
| M5 | **Extras.** Status, channels, communities, polls, location, disappearing messages, starred, broadcast lists, block, privacy settings, profile "recado". | Each feature has an end-to-end test. |
| M6 | **Calls.** LiveKit + MatrixRTC 1:1 and group voice/video. | Two clients hold a call locally. |
| M7 | **Production.** Real SMS provider adapter, deploy guide, monitoring, load test. | A load test passes the targets in section 12. |

## 8. Clients

### The Chama app (`app/`)

- Flutter (Dart), one codebase for Android, web, iOS and desktop. Android ships first.
- Matrix layer: famedly `matrix` Dart SDK with `flutter_vodozemac` for encryption. This is
  the same stack as FluffyChat, which already runs on all these platforms.
- Code layout: feature folders (`auth`, `chat_list`, `chat`, `group`, `profile`,
  `common`) and one thin service layer over the SDK. Widgets never call the SDK directly,
  so features are easy to test and to contribute.
- Layout: phones follow WhatsApp Android (tabs Conversas / Atualizações / Comunidades /
  Ligações, chat screen, contact picker, settings). Wide screens follow WhatsApp Web: left
  pane (header, search, filters Todas/Não lidas/Favoritas/Grupos, chat list), right pane
  (chat header, timeline, composer).
- Media is always fetched with auth and decrypted in the client.
- i18n: pt-BR first, English second, with Flutter's ARB files.
- No Google Play Services dependency in the core, so the app can also ship on F-Droid
  (FCM only in the Play Store build).

### Brand

- Own name, icon and palette. We copy interaction patterns, not WhatsApp's assets, logo
  or exact colours.
- Primary colour: flame orange `#E8590C` with warm neutrals. Colours are design tokens, so
  they change in one place. Brazilian flag colours and party colours are avoided, to stay
  neutral.

## 9. Error handling

- Clients keep an outbox: a message shows a clock icon until the server accepts it, and a
  red retry mark if sending fails. Retries are manual after 3 automatic attempts.
- Decryption failures show "Aguardando esta mensagem" (waiting for this message) and retry
  when keys arrive, as WhatsApp does.
- chama-id returns typed JSON errors (`{error: "rate_limited", retry_after}`); clients map
  them to pt-BR text.
- Sync drops show a yellow "Conectando…" banner; the SDKs reconnect with backoff.

## 10. Testing

- chama-id: `node --test` unit tests (phone normalisation, OTP expiry and tries, JWT claims,
  rate limits) plus an integration test against the real Synapse.
- Stack: `tools/smoke` signs in two users and exchanges an encrypted message.
- App: `flutter test` for logic and widgets; `integration_test` end-to-end against the
  local stack, on Chrome (fast) and on the Android emulator, with a Node test peer.

## 11. Operations and trust

- The operator can moderate public channels and act on reports, but cannot read
  encrypted chats. This is the core promise and must stay true in every milestone.
- Protections against operator abuse (section 5 and M4): account PIN, visible "joined"
  and "new device" events that the server cannot hide, cross-signing verification,
  short log retention (no IP logs beyond 7 days), open source, independent audits,
  reproducible Android builds, transparency reports.
- Honest limit: the operator of a Chama server still controls sign-in for that server, so
  it can block users. Federation lets other organisations run their own servers, but it
  does not protect users of one server from that server's operator. Account portability
  between servers is a later goal.
- License: AGPL-3.0 for server-side code, matching Synapse; clients AGPL-3.0 too, so forks
  stay open.

## 12. Scale (millions of users from launch)

Target for the first months: 5 million accounts, 1 million daily active users,
100 000 concurrent connections, peak 2 000 messages per second.

- **Synapse with workers from day one.** The dev Compose file already runs the worker
  layout, so production is the same shape with more replicas:
  - `sync` workers (several, behind the proxy, sticky per user) — the biggest load.
  - `client_reader` workers for other client reads.
  - `event_persister` workers (sharded stream writers) for writes.
  - `media_repository` worker; media stored on S3-compatible storage
    (`synapse-s3-storage-provider`), not on local disk.
  - `pusher` worker feeding Sygnal; `federation_sender` and `federation_reader` workers.
  - Redis for worker replication.
- **PostgreSQL** primary with streaming replicas and PgBouncer; regular `VACUUM` and
  state compression (`synapse_auto_compressor`).
- **chama-id** is stateless except SQLite in dev. In production it uses PostgreSQL (its
  own database) and runs as several replicas behind the proxy. Rate limits live in Redis.
- **Media** served through a CDN in front of the media worker (media is encrypted, so the
  CDN sees ciphertext only).
- **Known limit:** a single Synapse deployment is proven at hundreds of thousands of active
  users, not tens of millions. Beyond that, split users across several Chama homeservers
  that federate (for example by region). Federation makes this possible without changing
  the clients.
- **SMS cost:** millions of sign-in codes cost real money. chama-id has a provider
  interface so the cheapest provider (Zenvia, Infobip, Twilio, flash-call) can be swapped
  without client changes.
