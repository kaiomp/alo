import 'package:flutter/material.dart';

import 'app_services.dart';
import 'chat/voice/voice_recorder.dart';
import 'common/deps.dart';

/// Passed by MainActivity.runningEngine when a push starts the app while it
/// is not running: handle the push, show no screen.
const backgroundStartArg = '--alo-background';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final background = args.contains(backgroundStartArg);
  final services = await AppServices.start(background: background);
  if (!background) return runApp(services.app());
  // The user opens the app while the push engine runs: Android attaches the
  // same engine to the activity, so the screens start here, once.
  late final AppLifecycleListener listener;
  listener = AppLifecycleListener(
    onStateChange: (state) {
      if (state == AppLifecycleState.detached) return;
      listener.dispose();
      services.chat.setForeground(true, pushActive: services.push.active.value);
      runApp(services.app());
    },
  );
}

/// Starts the services and returns the app. Integration tests call this with
/// a fake recorder and picker.
Future<Widget> bootstrap({VoiceRecorder Function()? newRecorder, PickFile? pickFile}) async =>
    (await AppServices.start()).app(newRecorder: newRecorder, pickFile: pickFile);
