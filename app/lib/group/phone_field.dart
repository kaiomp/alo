import 'package:flutter/material.dart';

import '../auth/phone.dart';
import '../auth/phone_formatter.dart';
import '../common/deps.dart';
import '../l10n/app_localizations.dart';

/// "+55" number field with a full-width button under it. Calls [onUser] with
/// the Chama user ID (found through the chama-id directory) and the digits
/// once the number is valid and has an account; shows an error otherwise.
class PhoneLookupField extends StatefulWidget {
  const PhoneLookupField({super.key, required this.buttonLabel, required this.onUser, this.fieldKey, this.focusNode});

  final String buttonLabel;
  final Future<void> Function(String userId, String phoneDigits) onUser;

  /// Key of the field; the button gets `<value>_go`.
  final ValueKey<String>? fieldKey;
  final FocusNode? focusNode;

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
  Widget build(BuildContext context) {
    final key = widget.fieldKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: key,
          controller: _number,
          focusNode: widget.focusNode,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          inputFormatters: [BrPhoneFormatter()],
          decoration: InputDecoration(
            labelText: L10n.of(context).phoneNumber,
            hintText: '(11) 98765-4321',
            prefixText: '+55 ',
            errorText: _error,
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: key == null ? null : Key('${key.value}_go'),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.buttonLabel),
        ),
      ],
    );
  }
}
