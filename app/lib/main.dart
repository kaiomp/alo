import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'auth/id_client.dart';
import 'chat/voice/voice_recorder.dart';
import 'common/deps.dart';
import 'config.dart';
import 'services/chat_service.dart';
import 'services/models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await bootstrap());
}

/// Starts the services and returns the app. Integration tests call this with
/// a fake recorder and picker.
Future<Widget> bootstrap({VoiceRecorder Function()? newRecorder, PickFile? pickFile}) async {
  if (!kIsWeb) unawaited(getTemporaryDirectory().then(sweepVoiceFiles));
  final id = IdClient(chamaBaseUrl);
  final chat = await ChatService.start(homeserver: chamaBaseUrl, id: id);
  return Deps(
    chat: chat,
    id: id,
    newRecorder: newRecorder ?? RecordVoiceRecorder.new,
    pickFile: pickFile ?? _pickWithSystemPicker,
    child: const ChamaApp(),
  );
}

Future<PickedFile?> _pickWithSystemPicker({required bool image}) async {
  final f = await FilePicker.pickFile(type: image ? FileType.image : FileType.any);
  if (f == null) return null;
  return PickedFile(name: f.name, bytes: await f.readAsBytes());
}
