import 'package:chama/auth/phone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalises Brazilian mobile and landline input', () {
    expect(normalizePhone('+55', '(11) 98765-4321'), '5511987654321');
    expect(normalizePhone('55', '11 98765 4321'), '5511987654321');
    expect(normalizePhone('+55', '011 98765-4321'), '5511987654321');
    expect(normalizePhone('+55', '(21) 3456-7890'), '552134567890');
  });

  test('a Brazilian number pasted with its country code but no +', () {
    expect(normalizePhone('+55', '5511987654321'), '5511987654321');
    expect(normalizePhone('+55', '55 (11) 98765-4321'), '5511987654321');
    expect(normalizePhone('+55', '552134567890'), '552134567890');
    expect(normalizePhone('+55', '11987654321'), '5511987654321');
    // Area code 55 (Rio Grande do Sul) without the country code still works.
    expect(normalizePhone('+55', '55987654321'), '5555987654321');
  });

  test('a number field starting with + is a full number', () {
    expect(normalizePhone('+55', '+55 11 98765-4321'), '5511987654321');
    expect(normalizePhone('+55', '+49 176 62096183'), '4917662096183');
  });

  test('other country codes', () {
    expect(normalizePhone('+351', '912 345 678'), '351912345678');
  });

  test('rejects impossible numbers', () {
    expect(normalizePhone('+55', '98765-4321'), isNull); // no area code
    expect(normalizePhone('+55', '(11) 88765-4321'), isNull); // 11 digits must start with 9
    expect(normalizePhone('+55', ''), isNull);
    expect(normalizePhone('+55', 'abc'), isNull);
    expect(normalizePhone('+1', '123'), isNull);
  });

  test('formats for display', () {
    expect(formatPhone('5511987654321'), '+55 11 98765-4321');
    expect(formatPhone('552134567890'), '+55 21 3456-7890');
    expect(formatPhone('4917662096183'), '+4917662096183');
  });
}
