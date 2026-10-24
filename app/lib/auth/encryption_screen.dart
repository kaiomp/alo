import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/deps.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_service.dart';
import 'id_client.dart';

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
  bool _resetting = false; // new device, user has no key: SMS code step
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.status == CryptoStatus.setUp) _run(() async => _recoveryKey = await _chat.setUpEncryption());
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  ChatService get _chat => Deps.of(context).chat;

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
    final theme = Theme.of(context);
    final key = _recoveryKey;
    final List<Widget> body;
    if (key != null) {
      body = [
        Text(l.recoveryKeyTitle, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(l.recoveryKeyExplain, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        SelectableText(
          key,
          key: const Key('recovery_key'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: Text(l.copy),
          onPressed: () => Clipboard.setData(ClipboardData(text: key)),
        ),
        const SizedBox(height: 16),
        FilledButton(key: const Key('recovery_key_done'), onPressed: widget.onDone, child: Text(l.continueLabel)),
      ];
    } else if (widget.status == CryptoStatus.setUp) {
      body = [
        if (_error == null) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Text(l.settingUpEncryption, textAlign: TextAlign.center),
        ] else ...[
          Text(
            _error!,
            style: TextStyle(color: theme.colorScheme.error),
            textAlign: TextAlign.center,
          ),
          FilledButton(
            onPressed: () => _run(() async => _recoveryKey = await _chat.setUpEncryption()),
            child: Text(l.tryAgain),
          ),
        ],
      ];
    } else {
      body = [
        Text(l.newDeviceTitle, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(_resetting ? l.resetExplain : l.newDeviceExplain, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        TextField(
          key: const Key('encryption_input'),
          controller: _input,
          decoration: InputDecoration(
            labelText: _resetting ? l.code : l.recoveryKey,
            errorText: _error,
            errorMaxLines: 4,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
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
        // On the code step the same button sends a new code (a refused
        // reset spends the code).
        TextButton(
          key: const Key('no_recovery_key'),
          onPressed: _busy
              ? null
              : () => _run(() async {
                  await _chat.requestResetCode();
                  _input.clear();
                  setState(() => _resetting = true);
                }),
          child: Text(_resetting ? l.resendCode : l.noRecoveryKey),
        ),
      ];
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Icon(Icons.lock_outline, size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                ...body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
