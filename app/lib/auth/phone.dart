/// Phone number helpers. The server (chama-id) is the final judge of what is
/// valid; this only catches obvious typos and builds E.164 digits.
library;

/// Builds E.164 digits without '+' (e.g. `5511987654321`) from the country
/// code field and the number field. Returns null when the number cannot be
/// valid. A number field that starts with '+' is taken as a full number.
String? normalizePhone(String countryCode, String number) {
  final full = number.trim().startsWith('+');
  final cc = full ? '' : countryCode.replaceAll(RegExp(r'\D'), '');
  var national = number.replaceAll(RegExp(r'\D'), '');
  if (!full) national = national.replaceFirst(RegExp(r'^0+'), '');
  // Pasted with the country code but no '+': a Brazilian national number has
  // at most 11 digits, so 12 or 13 starting with 55 already carry it.
  if (cc == '55' && national.startsWith('55') && (national.length == 12 || national.length == 13)) {
    national = national.substring(2);
  }
  final digits = '$cc$national';
  if (digits.length < 8 || digits.length > 15) return null;
  if (digits.startsWith('55')) {
    final rest = digits.substring(2);
    // Brazil: 2-digit area code (no 0) + 8 digits (landline) or 9 + 8 digits (mobile).
    if (rest.length == 11 && rest[0] != '0' && rest[2] == '9') return digits;
    if (rest.length == 10 && rest[0] != '0') return digits;
    return null;
  }
  return digits;
}

/// Pretty form for display: `+55 11 98765-4321`. Other countries: `+<digits>`.
String formatPhone(String digits) {
  if (digits.startsWith('55') && (digits.length == 12 || digits.length == 13)) {
    final area = digits.substring(2, 4);
    final local = digits.substring(4);
    final cut = local.length - 4;
    return '+55 $area ${local.substring(0, cut)}-${local.substring(cut)}';
  }
  return '+$digits';
}

/// Brazilian national number as typed: "(11) 98765-4321" (or "(11) 3456-7890"
/// for landlines). Anything starting with '+' is left alone (pasted
/// international number).
String maskBrPhone(String input) {
  if (input.trimLeft().startsWith('+')) return input;
  final d = input.replaceAll(RegExp(r'\D'), '');
  final digits = d.length > 11 ? d.substring(0, 11) : d;
  if (digits.isEmpty) return '';
  if (digits.length <= 2) return '($digits';
  final area = digits.substring(0, 2);
  final local = digits.substring(2);
  // Mobiles have 9 digits after the area code, landlines 8.
  final cut = local.length > 8 ? 5 : 4;
  if (local.length <= cut) return '($area) $local';
  return '($area) ${local.substring(0, cut)}-${local.substring(cut)}';
}
