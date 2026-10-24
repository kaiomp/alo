import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> _keys(String locale) {
  final arb = jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync()) as Map<String, dynamic>;
  return arb.keys.where((k) => !k.startsWith('@')).toSet();
}

void main() {
  test('English strings cover every Portuguese key and nothing else', () {
    expect(_keys('en'), _keys('pt'));
  });
}
