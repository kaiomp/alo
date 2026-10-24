import 'package:flutter/widgets.dart';

import '../auth/id_client.dart';
import '../chat/voice/voice_recorder.dart';
import '../contacts/contacts_service.dart';
import '../services/chat_service.dart';
import '../services/models.dart';
import '../services/push.dart';
import 'notifications.dart';

/// Picks one file; [image] limits the picker to photos. Null when cancelled.
typedef PickFile = Future<PickedFile?> Function({required bool image});

/// Opens the system share sheet with [text].
typedef ShareText = Future<void> Function(String text);

/// App-wide services, handed down the tree. Tests swap the recorder, the
/// file picker and the share sheet for fakes.
class Deps extends InheritedWidget {
  const Deps({
    super.key,
    required this.chat,
    required this.id,
    required this.contacts,
    required this.notifications,
    required this.push,
    required this.newRecorder,
    required this.pickFile,
    required this.shareText,
    required super.child,
  });

  final ChatService chat;
  final IdClient id;
  final ContactsService contacts;
  final Notifications notifications;
  final PushService push;
  final VoiceRecorder Function() newRecorder;
  final PickFile pickFile;
  final ShareText shareText;

  static Deps of(BuildContext context) => context.getInheritedWidgetOfExactType<Deps>()!;

  @override
  bool updateShouldNotify(Deps oldWidget) => false;
}
