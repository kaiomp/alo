import 'package:flutter/material.dart';

import '../auth/phone.dart';
import '../common/deps.dart';
import '../l10n/app_localizations.dart';

/// "+55" + number field with a button. Calls [onUser] with the Chama user ID
/// (found through the chama-id directory) and the digits once the number is
/// valid and has an account; shows an error otherwise.
class PhoneLookupField extends StatefulWidget {
  const PhoneLookupField({super.key, required this.buttonLabel, required this.onUser, this.fieldKey});

  final String buttonLabel;
  final Future<void> Function(String userId, String phoneDigits) onUser;
  final Key? fieldKey;

  @override
  State<PhoneLookupField> createState() => _PhoneLookupFieldState();
}

class _PhoneLookupFieldState extends State<PhoneLookupField> {
  final _number = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = L10n.of(context);
    final digits = normalizePhone('+55', _number.text);
    if (digits == null) return setState(() => _error = l.errInvalidPhone);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final userId = await Deps.of(context).chat.findByPhone(digits);
      if (!mounted) return;
      if (userId == null) {
        setState(() => _error = l.notOnChama);
        return;
      }
      await widget.onUser(userId, digits);
      if (mounted) _number.clear();
    } catch (_) {
      if (mounted) setState(() => _error = l.errUnknown);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TextField(
          key: widget.fieldKey,
          controller: _number,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: L10n.of(context).phoneNumber, prefixText: '+55 ', errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: FilledButton(
          key: widget.fieldKey == null ? null : Key('${(widget.fieldKey as ValueKey).value}_go'),
          onPressed: _busy ? null : _submit,
          child: Text(widget.buttonLabel),
        ),
      ),
    ],
  );
}
