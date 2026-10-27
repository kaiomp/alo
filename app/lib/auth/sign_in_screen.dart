import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/deps.dart';
import '../common/theme.dart';
import '../l10n/app_localizations.dart';
import 'id_client.dart';
import 'onboarding.dart';
import 'phone.dart';
import 'phone_formatter.dart';

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

  bool get _brazil => _cc.text.replaceAll(RegExp(r'\D'), '') == '55';

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

  Future<void> _editCountry() async {
    final l = L10n.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.countryCode),
        content: TextField(
          key: const Key('country_code'),
          controller: _cc,
          autofocus: true,
          keyboardType: TextInputType.phone,
          onSubmitted: (_) => Navigator.pop(context),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l.continueLabel))],
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final phone = _phone;
    final scheme = Theme.of(context).colorScheme;
    final error = _error == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              key: const Key('sign_in_error'),
              style: TextStyle(color: scheme.error),
            ),
          );
    final cta = FilledButton(
      key: const Key('sign_in_next'),
      onPressed: _busy ? null : (phone == null ? _sendCode : _verify),
      child: _busy
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(l.next),
    );

    if (phone == null) {
      final cc = _cc.text.trim().startsWith('+') ? _cc.text.trim() : '+${_cc.text.trim()}';
      return OnboardingScaffold(
        cta: cta,
        children: [
          OnboardingTitle(title: l.signInTitle, body: l.signInExplain(l.appName)),
          TextField(
            key: const Key('phone_number'),
            controller: _number,
            autofocus: true,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [if (_brazil) BrPhoneFormatter()],
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              hintText: '(11) 98765-4321',
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 6, right: 4),
                child: TextButton(
                  key: const Key('country_button'),
                  onPressed: _editCountry,
                  style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _brazil ? '${l.countryBrazil} $cc' : cc,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      Icon(Icons.arrow_drop_down, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              constraints: const BoxConstraints(minHeight: 56),
            ),
            onSubmitted: (_) => _sendCode(),
          ),
          ?error,
        ],
      );
    }

    return OnboardingScaffold(
      cta: cta,
      children: [
        OnboardingTitle(title: l.codeTitle(formatPhone(phone)), body: l.codeExplain),
        _CodeCells(controller: _code, onCompleted: _verify),
        ?error,
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: _busy || _resendIn > 0 ? null : _sendCode,
              child: Text(
                _resendIn > 0 ? l.resendIn(_resendIn) : l.resendCode,
                style: const TextStyle(fontFeatures: tabularFigures),
              ),
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
        ),
      ],
    );
  }
}

/// Six boxes for the SMS code over one hidden field (so paste and SMS
/// autofill work). Calls [onCompleted] once six digits are in.
class _CodeCells extends StatefulWidget {
  const _CodeCells({required this.controller, required this.onCompleted});
  final TextEditingController controller;
  final VoidCallback onCompleted;

  @override
  State<_CodeCells> createState() => _CodeCellsState();
}

class _CodeCellsState extends State<_CodeCells> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    widget.controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final code = widget.controller.text;
    return LayoutBuilder(
      builder: (context, c) => Stack(
        children: [
          // Drawing only: screen readers get the field below.
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i > 0) SizedBox(width: i == 3 ? 16 : 8),
                  Container(
                    // 48 wide, narrower on small phones.
                    width: ((c.maxWidth - 56) / 6).clamp(36.0, 48.0),
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        width: 2,
                        color: _focus.hasFocus && i == code.length.clamp(0, 5) ? scheme.primary : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      i < code.length ? code[i] : '',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        fontFeatures: tabularFigures,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              alwaysIncludeSemantics: true,
              child: TextField(
                key: const Key('sms_code'),
                controller: widget.controller,
                focusNode: _focus,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: 6,
                showCursor: false,
                enableInteractiveSelection: false,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: L10n.of(context).smsCodeLabel,
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  counterText: '',
                  filled: false,
                  border: InputBorder.none,
                ),
                onChanged: (v) {
                  if (v.length == 6) widget.onCompleted();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
