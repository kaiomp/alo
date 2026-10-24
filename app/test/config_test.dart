import 'package:chama/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug builds default to the local stack', () {
    expect(baseUrlFor('', release: false, android: true), Uri.parse('http://10.0.2.2:8080'));
    expect(baseUrlFor('', release: false, android: false), Uri.parse('http://localhost:8080'));
    expect(baseUrlFor('http://192.168.0.5:8080', release: false, android: true).host, '192.168.0.5');
  });

  test('release builds refuse a missing or cleartext server URL', () {
    expect(() => baseUrlFor('', release: true, android: true), throwsStateError);
    expect(() => baseUrlFor('http://chama.example', release: true, android: true), throwsStateError);
    expect(() => baseUrlFor('https://', release: true, android: true), throwsStateError);
    expect(baseUrlFor('https://chama.example', release: true, android: true), Uri.parse('https://chama.example'));
  });
}
