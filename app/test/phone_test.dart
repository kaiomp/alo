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

  test('masks a Brazilian number while typing', () {
    expect(maskBrPhone(''), '');
    expect(maskBrPhone('1'), '(1');
    expect(maskBrPhone('119'), '(11) 9');
    expect(maskBrPhone('1134567890'), '(11) 3456-7890');
    expect(maskBrPhone('11987654321'), '(11) 98765-4321');
    expect(maskBrPhone('(11) 98765-43210'), '(11) 98765-4321'); // extra digit dropped
    expect(maskBrPhone('+4917662096183'), '+4917662096183');
    expect(normalizePhone('+55', maskBrPhone('11987654321')), '5511987654321');
  });

  test('address-book numbers: national, international, carrier code, old mobiles', () {
    expect(normalizeContactPhone('(11) 98765-4321'), '5511987654321');
    expect(normalizeContactPhone('+55 11 98765-4321'), '5511987654321');
    expect(normalizeContactPhone('011 98765-4321'), '5511987654321');
    expect(normalizeContactPhone('0 15 11 98765-4321'), '5511987654321'); // carrier 15
    expect(normalizeContactPhone('0xx21 3456-7890'), '552134567890');
    expect(normalizeContactPhone('11 8765-4321'), '5511987654321'); // saved before the ninth digit
    expect(normalizeContactPhone('+55 11 8765-4321'), '5511987654321');
    expect(normalizeContactPhone('(21) 3456-7890'), '552134567890'); // landline stays
    expect(normalizeContactPhone('+49 176 62096183'), '4917662096183');
  });

  test('address-book entries that are not phone numbers', () {
    expect(normalizeContactPhone('190'), isNull);
    expect(normalizeContactPhone('*144'), isNull);
    expect(normalizeContactPhone(''), isNull);
    expect(normalizeContactPhone('98765-4321'), isNull); // no area code
  });

  test('a foreign number saved without "+" is no number, never a guessed Brazilian one', () {
    // Without the 0 of a carrier code in front, 12 or 13 digits not starting
    // with 55 cannot be read as Brazilian: a wrong guess would show a
    // stranger under this contact's name.
    expect(normalizeContactPhone('447911123456'), isNull);
    expect(normalizeContactPhone('4917662096183'), isNull);
    expect(normalizeContactPhone('2111987654321'), isNull);
    expect(normalizeContactPhone('00 44 7911 123456'), isNull); // 00: international prefix, not a carrier
    expect(normalizeContactPhone('+44 7911 123456'), '447911123456');
    // The carrier code habit keeps working.
    expect(normalizeContactPhone('0 21 11 98765-4321'), '5511987654321');
    expect(normalizeContactPhone('021 11 3456-7890'), '551134567890');
    expect(normalizeContactPhone('55 11 98765-4321'), '5511987654321');
  });
}
