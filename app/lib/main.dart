import 'package:flutter/material.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;

import 'services/database.dart';

/// Boot check: the encryption library and the local database load on this
/// platform. Task 9 replaces this file with the real entry point.
/// The status also goes to the log and (on web) to the page title, so a
/// script can read it.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var status = 'criptografia e banco prontos';
  try {
    await vod.init();
    await openDatabase('boot_check');
  } catch (e) {
    status = 'falhou: $e';
  }
  debugPrint('boot: $status');
  runApp(
    MaterialApp(
      title: 'boot: $status',
      home: Scaffold(body: Center(child: Text('Chama — $status'))),
    ),
  );
}
