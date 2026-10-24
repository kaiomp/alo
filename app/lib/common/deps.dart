import 'package:flutter/widgets.dart';

import '../auth/id_client.dart';
import '../chat/voice/voice_recorder.dart';
import '../services/chat_service.dart';
import '../services/models.dart';

/// Picks one file; [image] limits the picker to photos. Null when cancelled.
typedef PickFile = Future<PickedFile?> Function({required bool image});

/// App-wide services, handed down the tree. Tests swap the recorder and the
/// file picker for fakes.
class Deps extends InheritedWidget {
  const Deps({
    super.key,
    required this.chat,
    required this.id,
    required this.newRecorder,
    required this.pickFile,
    required super.child,
  });

  final ChatService chat;
  final IdClient id;
  final VoiceRecorder Function() newRecorder;
  final PickFile pickFile;

  static Deps of(BuildContext context) => context.getInheritedWidgetOfExactType<Deps>()!;

  @override
  bool updateShouldNotify(Deps oldWidget) => false;
}
