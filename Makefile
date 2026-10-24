COMPOSE = docker compose -f server/compose.yaml --env-file server/data/.env
# Same image as compose.yaml; used to delete files that Synapse (uid 991) created.
SYNAPSE_IMAGE := $(shell awk '/image: ghcr.io\/element-hq\/synapse:/ {print $$2; exit}' server/compose.yaml)
NO_ENV = echo "server/data/.env does not exist yet: run make up first"

.PHONY: up down logs reset test smoke app-test app-web app-android app-e2e-web app-e2e-android app-apk app-aab

up:
	./server/scripts/init.sh
	$(COMPOSE) up -d --build --wait

down:
	@if [ -f server/data/.env ]; then $(COMPOSE) down; else $(NO_ENV); fi

logs:
	@if [ -f server/data/.env ]; then $(COMPOSE) logs -f --tail=100; else $(NO_ENV); fi

# A plain rm fails on Linux for files owned by uid 991, so fall back to a container. No sudo needed.
reset:
	@if [ -f server/data/.env ]; then $(COMPOSE) down -v || true; fi
	rm -rf server/data 2>/dev/null || docker run --rm -v "$(CURDIR)/server:/s" --entrypoint rm $(SYNAPSE_IMAGE) -rf /s/data

test:
	pnpm -r test
	cd app && flutter test

smoke: up
	pnpm --filter smoke start

app-test:
	cd app && flutter test

# Run the app against the local stack (make up first).
app-web:
	cd app && ./scripts/build-vodozemac-web.sh && flutter run -d chrome

app-android:
	cd app && flutter run -d $${ANDROID_SERIAL:-$$(adb devices | awk '/^emulator-/{print $$1; exit}')}

# End-to-end: the app chats with tools/peer (needs make up).
app-e2e-web:
	cd app && ./scripts/e2e.sh chrome

app-e2e-android:
	cd app && ./scripts/e2e.sh android && ./scripts/e2e.sh android integration_test/contacts_test.dart && \
	  ./scripts/ntfy-setup.sh && ./scripts/e2e.sh android integration_test/push_test.dart

# Release builds need CHAMA_BASE_URL (https: release builds refuse anything
# else) and the signing key in CHAMA_KEYSTORE* (app/README.md). pub get first:
# a GeneratedPluginRegistrant left by an integration-test run still names the
# test-only plugin and breaks javac.
NEED_HTTPS = @case "$(CHAMA_BASE_URL)" in https://?*) ;; *) echo "Set CHAMA_BASE_URL=https://… (make $@ CHAMA_BASE_URL=https://chama.example)"; exit 1 ;; esac

# APKs of the fdroid flavor (no Google code), one per ABI:
# app/build/app/outputs/flutter-apk/app-<abi>-fdroid-release.apk
app-apk:
	$(NEED_HTTPS)
	cd app && flutter pub get && flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64 \
	  --dart-define=CHAMA_BASE_URL=$(CHAMA_BASE_URL)

# Play Store bundle: the play flavor adds FCM through UnifiedPush's embedded
# distributor. app/build/app/outputs/bundle/playRelease/app-play-release.aab
app-aab:
	$(NEED_HTTPS)
	cd app && flutter pub get && flutter build appbundle --release --flavor play --dart-define=CHAMA_BASE_URL=$(CHAMA_BASE_URL)
