import 'package:flutter/services.dart';

import 'phone.dart';

/// Applies [maskBrPhone] while typing; the cursor stays at the end.
class BrPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text;
    // Backspace over a mask character deletes the digit before it.
    if (oldValue.text.length - text.length == 1 &&
        oldValue.text.replaceAll(RegExp(r'\D'), '') == text.replaceAll(RegExp(r'\D'), '')) {
      final d = text.replaceAll(RegExp(r'\D'), '');
      text = d.isEmpty ? '' : d.substring(0, d.length - 1);
    }
    final masked = maskBrPhone(text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}
