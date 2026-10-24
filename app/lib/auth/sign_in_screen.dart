import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/deps.dart';
import '../l10n/app_localizations.dart';
import 'id_client.dart';
import 'phone.dart';

/// Phone number, then SMS code, then Matrix login (spec section 4).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _cc = TextEditingController(text: '+55');
  final _number = TextEditingController();
  final _code = TextEditingController();
  String? _phone; // set once the SMS is sent: we are on the code step
  String? _error;
  bool _busy = false;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _cc.dispose();
    _number.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on IdError catch (e) {
      if (mounted) setState(() => _error = e.message(L10n.of(context)));
    } catch (e) {
      if (mounted) setState(() => _error = L10n.of(context).errUnknown);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
    final digits = _phone ?? normalizePhone(_cc.text, _number.text);
    if (digits == null) throw const IdError('invalid_phone');
    final r = await Deps.of(context).id.requestCode(digits);
    _timer?.cancel();
    setState(() {
      _phone = r.phone;
      _resendIn = r.retryAfter;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 1) t.cancel();
      setState(() => _resendIn--);
    });
  });

  Future<void> _verify() => _run(() async {
    final deps = Deps.of(context);
    final login = await deps.id.verifyCode(_phone!, _code.text.trim());
    await deps.chat.signIn(login);
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final phone = _phone;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 32),
                Icon(Icons.local_fire_department, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  phone == null ? l.signInTitle : l.codeTitle(formatPhone(phone)),
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(phone == null ? l.signInExplain : l.codeExplain, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                if (phone == null)
                  Row(
                    children: [
                      SizedBox(
                        width: 80,
                        child: TextField(
                          key: const Key('country_code'),
                          controller: _cc,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(labelText: l.countryCode),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          key: const Key('phone_number'),
                          controller: _number,
                          autofocus: true,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(labelText: l.phoneNumber, hintText: '(11) 98765-4321'),
                          onSubmitted: (_) => _sendCode(),
                        ),
                      ),
                    ],
                  )
                else
                  TextField(
                    key: const Key('sms_code'),
                    controller: _code,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
                    decoration: InputDecoration(labelText: l.code, counterText: ''),
                    onChanged: (v) {
                      if (v.length == 6) _verify();
                    },
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('sign_in_error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('sign_in_next'),
                  onPressed: _busy ? null : (phone == null ? _sendCode : _verify),
                  child: _busy
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l.next),
                ),
                if (phone != null) ...[
                  TextButton(
                    onPressed: _busy || _resendIn > 0 ? null : _sendCode,
                    child: Text(_resendIn > 0 ? l.resendIn(_resendIn) : l.resendCode),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _timer?.cancel();
                            _phone = null;
                            _code.clear();
                            _error = null;
                          }),
                    child: Text(l.wrongNumber),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
