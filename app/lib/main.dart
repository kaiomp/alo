import 'package:flutter/material.dart';

import 'app_services.dart';
import 'chat/voice/voice_recorder.dart';
import 'common/deps.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp((await AppServices.start()).app());
}

/// Starts the services and returns the app. Integration tests call this with
/// a fake recorder and picker.
Future<Widget> bootstrap({VoiceRecorder Function()? newRecorder, PickFile? pickFile}) async =>
    (await AppServices.start()).app(newRecorder: newRecorder, pickFile: pickFile);
