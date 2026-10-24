import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/deps.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_service.dart';
import 'id_client.dart';
import 'onboarding.dart';

/// Runs once per device after sign-in (spec §5):
/// - first device of the account: makes the keys and shows the recovery key;
/// - new device: unlock with the recovery key, or reset with an SMS code.
class EncryptionScreen extends StatefulWidget {
  const EncryptionScreen({super.key, required this.status, required this.onDone});
  final CryptoStatus status;
  final VoidCallback onDone;

  @override
  State<EncryptionScreen> createState() => _EncryptionScreenState();
}

class _EncryptionScreenState extends State<EncryptionScreen> {
  final _input = TextEditingController();
  String? _recoveryKey; // set when there is a key to show
  bool _saved = false; // "Guardei minha chave" ticked
  bool _resetting = false; // new device, user has no key: SMS code step
  bool _busy = false;
  String? _error;
  int _resendIn = 0; // seconds until "Reenviar SMS" works again
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.status == CryptoStatus.setUp) _run(() async => _recoveryKey = await _chat.setUpEncryption());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  ChatService get _chat => Deps.of(context).chat;

  Future<void> _requestCode() => _run(() async {
    final retryAfter = await _chat.requestResetCode();
    if (retryAfter == null || !mounted) return; // signed out: back to sign-in
    _input.clear();
    _timer?.cancel();
    setState(() {
      _resetting = true;
      _resendIn = retryAfter;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 1) t.cancel();
      setState(() => _resendIn--);
    });
  });

  Future<void> _run(Future<void> Function() action, {String Function(L10n)? onError}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on IdError catch (e) {
      if (mounted) setState(() => _error = e.message(L10n.of(context)));
    } catch (_) {
      if (mounted) setState(() => _error = (onError ?? (l) => l.errUnknown)(L10n.of(context)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final key = _recoveryKey;
    // A way out on every step but the key display: some errors (number
    // moved, session expired) need a new sign-in.
    final signOut = TextButton(
      key: const Key('encryption_sign_out'),
      style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
      onPressed: _busy ? null : () => _run(_chat.signOut),
      child: Text(l.signOut),
    );

    if (key != null) {
      return OnboardingScaffold(
        cta: FilledButton(
          key: const Key('recovery_key_done'),
          onPressed: _saved ? widget.onDone : null,
          child: Text(l.continueLabel),
        ),
        children: [
          OnboardingTitle(title: l.recoveryKeyTitle, body: l.recoveryKeyExplain),
          _KeyCard(recoveryKey: key),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              style: tonalButton(context),
              icon: const Icon(Icons.copy, size: 18),
              label: Text(l.copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: key));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.copied)));
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const Key('recovery_key_saved'),
            value: _saved,
            onChanged: (v) => setState(() => _saved = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(l.recoveryKeySaved, style: const TextStyle(fontSize: 15)),
          ),
        ],
      );
    }

    if (widget.status == CryptoStatus.setUp) {
      return OnboardingScaffold(
        cta: _error == null
            ? null
            : FilledButton(
                onPressed: () => _run(() async => _recoveryKey = await _chat.setUpEncryption()),
                child: Text(l.tryAgain),
              ),
        below: [if (_error != null) signOut],
        children: [
          if (_error == null)
            Row(
              children: [
                const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                const SizedBox(width: 16),
                Expanded(child: Text(l.settingUpEncryption, style: const TextStyle(fontSize: 16))),
              ],
            )
          else
            Text(_error!, style: TextStyle(color: scheme.error)),
        ],
      );
    }

    return OnboardingScaffold(
      cta: FilledButton(
        key: const Key('encryption_next'),
        onPressed: _busy
            ? null
            : () => _resetting
                  ? _run(() async => _recoveryKey = await _chat.resetEncryption(_input.text.trim()))
                  : _run(() async {
                      await _chat.unlockEncryption(_input.text);
                      widget.onDone();
                    }, onError: (l) => l.errRecoveryKey),
        child: Text(_resetting ? l.resetConfirm : l.next),
      ),
      below: [signOut],
      children: [
        OnboardingTitle(title: l.newDeviceTitle, body: _resetting ? l.resetExplain : l.newDeviceExplain),
        TextField(
          key: const Key('encryption_input'),
          controller: _input,
          style: _resetting ? null : const TextStyle(fontFamily: monoFontFamily, fontSize: 16),
          decoration: InputDecoration(
            labelText: _resetting ? l.code : l.recoveryKey,
            errorText: _error,
            errorMaxLines: 4,
          ),
        ),
        const SizedBox(height: 8),
        // On the code step the same button sends a new code (a refused
        // reset spends the code).
        TextButton(
          key: const Key('request_reset_code'),
          onPressed: _busy || _resendIn > 0 ? null : _requestCode,
          child: Text(
            !_resetting
                ? l.noRecoveryKey
                : _resendIn > 0
                ? l.resendIn(_resendIn)
                : l.resendCode,
          ),
        ),
      ],
    );
  }
}

/// The recovery key as a grid of 4-character groups in a monospace font.
class _KeyCard extends StatelessWidget {
  const _KeyCard({required this.recoveryKey});
  final String recoveryKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = recoveryKey.trim().split(RegExp(r'\s+'));
    final rows = [for (var i = 0; i < groups.length; i += 4) groups.sublist(i, (i + 4).clamp(0, groups.length))];
    const style = TextStyle(fontFamily: monoFontFamily, fontSize: 18, height: 28 / 18, fontWeight: FontWeight.w500);
    return Container(
      key: const Key('recovery_key'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(16)),
      child: SelectionArea(
        child: Column(
          children: [
            for (final row in rows)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [for (final g in row) Text(g, style: style.copyWith(color: scheme.onSurface))],
              ),
          ],
        ),
      ),
    );
  }
}
