# Chama

Chama é um mensageiro livre, aberto e com criptografia de ponta a ponta, feito para o Brasil.

Chama is a free, open, end-to-end encrypted messenger, made for Brazil.

## Run locally

Prerequisites: Docker, Node 26, pnpm.

```sh
pnpm install && make up && make smoke
```

- `make test` runs the unit tests (no stack needed; needs Flutter too, for the app tests).
- `server/scripts/check.sh` runs the acceptance checks against the running stack.
- `make smoke` signs in two users and sends an encrypted message between them.
- `make down` stops the stack; `make reset` also deletes all its data.

The local stack is for development only. In dev mode the code `000000` signs in any
phone number, so the stack listens on localhost only (`http://localhost:8080`).

### App

The Chama app lives in `app/` (Flutter). See [app/README.md](app/README.md).
Prerequisites: Flutter 3.47.8, the Android SDK with the NDK and an emulator (AVD), Chrome, and
rustup. Android builds need rustup too: vodozemac compiles from Rust on every build.

Design: [docs/design/2026-10-24-architecture.md](docs/design/2026-10-24-architecture.md)
chama-id API: [docs/chama-id-api.md](docs/chama-id-api.md)

## License

GNU Affero General Public License v3.0 only (AGPL-3.0-only). See [LICENSE](LICENSE).
