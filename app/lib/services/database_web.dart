import 'package:matrix/matrix.dart';

/// Web: the SDK keeps everything in IndexedDB.
Future<DatabaseApi> openDatabase(String name) => MatrixSdkDatabase.init(name);
