import 'package:alo/services/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('encryption library and local database load on this platform', (tester) async {
    await vod.init();
    final db = await openDatabase('boot_check');
    expect(await db.getFile(Uri.parse('mxc://alo.test/nothing')), isNull);
  });
}
