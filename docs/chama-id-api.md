# chama-id API

chama-id is the sign-in service (spec §4). Clients reach it through the proxy under `/id/v1`.
All bodies are JSON. Every error is `{"error": "<code>"}`, sometimes with extra fields.

## Routes

| Method | Path | Auth |
|---|---|---|
| GET | `/id/v1/health` | none |
| POST | `/id/v1/otp/request` | none |
| POST | `/id/v1/otp/verify` | none |
| POST | `/id/v1/directory/lookup` | `Authorization: Bearer <Matrix access token>` |
| POST | `/id/v1/account/reset-identity` | `Authorization: Bearer <Matrix access token>` |

### `GET /id/v1/health`

Response: `{"ok": true}`

### `POST /id/v1/otp/request`

Sends a 6-digit code by SMS.

- Request: `{"phone": "<number>"}`. Brazilian national (`11987654321`, `(11) 98765-4321`)
  or international (`+55 11 98765-4321`) format.
- Response: `{"phone": "5511987654321", "retry_after": 60}`. `phone` is the E.164 number
  without `+`. `retry_after` is the seconds until the next code can be requested.
- Errors: `invalid_phone` 400, `rate_limited` 429 (with `retry_after` in seconds).

### `POST /id/v1/otp/verify`

Checks the code, then finds or creates the phone's account.

- Request: `{"phone": "<number>", "code": "123456"}`
- Response:

  ```json
  {
    "phone": "5511987654321",
    "user_id": "@u7k3m9q2x4w8a1b5c:chama.test",
    "homeserver": "http://localhost:8080",
    "new_account": true,
    "login_token": "<JWT>"
  }
  ```

  - `user_id` is opaque (`@u` + 16 lowercase base32 characters). It never holds the phone.
  - `new_account` is true for a new phone, and for a recycled number whose old account was
    retired (no activity for 45 days).
  - `login_token` is a JWT for Matrix `POST /_matrix/client/v3/login` with
    `{"type": "org.matrix.login.jwt", "token": "<JWT>"}`. It expires after 120 s.
  - `homeserver` is the public base URL, for production clients. Clients must use their own
    configured base URL to reach the server: in development the Android emulator reaches the
    host at `http://10.0.2.2:8080`, not at the `localhost` URL in this field.
- Errors: `invalid_phone` 400, `invalid_code` 400 (wrong code, or no code requested),
  `expired` 400, `too_many_attempts` 429 (5 wrong tries on this code),
  `rate_limited` 429 (10 wrong tries in 24 h, with `retry_after`).

### `POST /id/v1/directory/lookup`

Finds which contacts have an account.

- Request: `{"hashes": ["<hash>", ...]}`, at most 1000 hashes.
- Hash input: the lowercase hex SHA-256 of the E.164 digits without `+`. Example: for
  `+55 11 98765-4321` hash the string `5511987654321`.
- Response: `{"registered": [{"hash": "<hash>", "user_id": "@u...:chama.test"}]}`. Only
  registered hashes are listed. A duplicate hash is listed once.
- Errors: `invalid_token` 401, `bad_request` 400 (not an array, over 1000 items, or an item
  that is not 64 lowercase hex characters), `rate_limited` 429 (with `retry_after`).

### `POST /id/v1/account/reset-identity`

For a new phone without the recovery key (spec §4, §5). It needs a valid access token for the
account, a second, fresh SMS code for the same phone, and the new **public** cross-signing
keys. The phone makes the keys; private keys never leave it.

- Request:

  ```json
  {
    "phone": "<number>",
    "code": "123456",
    "keys": {
      "master_key": { "user_id": "@u...", "usage": ["master"], "keys": { "ed25519:<pub>": "<pub>" } },
      "self_signing_key": { "user_id": "@u...", "usage": ["self_signing"], "keys": { "...": "..." }, "signatures": { "...": "..." } },
      "user_signing_key": { "user_id": "@u...", "usage": ["user_signing"], "keys": { "...": "..." }, "signatures": { "...": "..." } }
    }
  }
  ```

  `keys` is the body of Matrix `POST /_matrix/client/v3/keys/device_signing/upload`: the
  self-signing and user-signing keys are signed by the new master key. It must hold exactly
  these three keys. Each key has `user_id` equal to the caller, a `usage` of exactly its own
  type, and only the fields `user_id`, `usage`, `keys` and `signatures`, so no private key can
  be sent. The request body is capped at 8 KiB.
- Response: `{"logged_out_devices": 1}` (how many other devices were logged out).
- Errors: `invalid_token` 401, `invalid_phone` 400, `forbidden` 403 (the token's account is
  not the phone's current account), `bad_request` 400 (`keys` missing or malformed),
  `no_identity` 409, `invalid_code` 400, `expired` 400, `too_many_attempts` 429,
  `rate_limited` 429, `invalid_keys` 400 (Synapse refused the keys, for example a bad
  signature; the code is spent and other devices are already logged out, so retry with a new code).

Flow:

1. The client signs in (request + verify + Matrix login) and gets an access token.
2. The client requests a second code (`otp/request`) and the user types it.
3. The client makes new cross-signing keys and calls `reset-identity` with its access token,
   the code and the public keys. chama-id checks, in this order: the token, that the token's
   account is the phone's current account, the shape of `keys`, and that the account has a
   master cross-signing key. Only then is the code checked and spent.
4. chama-id logs out every other device of the account (their access tokens stop working).
5. chama-id uploads the keys as the user through its Matrix application service (Synapse
   asks no user-interactive auth from an application service). Contacts then see
   "Security code changed".

`no_identity` (409) means the account has no master cross-signing key yet, so there is
nothing to reset. The code is not spent. The client just bootstraps cross-signing itself: the
first upload of cross-signing keys needs no user-interactive auth.

## Limits

| Limit | Value | Dev mode (`CHAMA_DEV=1`) |
|---|---|---|
| Code lifetime | 300 s | same |
| Wrong tries per code | 5 | same |
| Codes per phone | 1 per 60 s (while a code is pending), 5 per 24 h | same |
| Wrong tries per phone | 10 per 24 h | same |
| Code requests per IP | 10 per hour | ×100 |
| Lookups per IP | 30 per hour | ×100 |
| Lookups per user | 30 per hour | ×100 |
| reset-identity calls per IP | 10 per hour | ×100 |
| Body size | 16 KiB (lookup: 96 KiB, reset-identity: 8 KiB) | same |

- Per-IP limits count an IPv6 address by its /64. An IPv4-mapped IPv6 address counts as IPv4.
- Windows roll: a call leaves the count once it is older than the window.
- `rate_limited` always carries `retry_after` in seconds.
- In dev mode the code `000000` is accepted for any phone that has requested a code.

## Other errors

- `bad_request` 400: the body is not a JSON object, a field has the wrong type, or the body
  is too large.
- `not_found` 404: unknown route.
- `internal` 500: anything else (the cause is in the chama-id log).
