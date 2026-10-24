import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'auth/id_client.dart';
import 'chat/voice/voice_recorder.dart';
import 'common/deps.dart';
import 'common/notifications.dart';
import 'config.dart';
import 'contacts/address_book.dart';
import 'contacts/contacts_service.dart';
import 'services/chat_service.dart';
import 'services/models.dart';
import 'services/push.dart';

/// Everything the app runs, started once per process. A push can start it
/// with no screen (main.dart); the UI then attaches to the same instance.
class AppServices with WidgetsBindingObserver {
  AppServices._(this.id, this.chat, this.contacts, this.notifications, this.push) {
    WidgetsBinding.instance.addObserver(this);
  }

  static Future<AppServices> start({bool background = false}) async {
    if (!kIsWeb) unawaited(getTemporaryDirectory().then(sweepVoiceFiles));
    final id = IdClient(chamaBaseUrl);
    final chat = await ChatService.start(homeserver: chamaBaseUrl, id: id, background: background);
    final prefs = await SharedPreferences.getInstance();
    final contacts = ContactsService(chat, onAndroid ? DeviceAddressBook() : NoAddressBook(), prefs);
    await contacts.ready;
    final notifications = Notifications()
      ..onReply = chat.sendQuickReply
      ..clearOnSignOut(chat.loggedIn);
    // onPush before init: a push that started the app comes right after it.
    final push = PushService(chat, prefs)..onPush = (roomId, eventId) => notifications.showPush(chat, roomId, eventId);
    await notifications.init();
    await push.init();
    return AppServices._(id, chat, contacts, notifications, push);
  }

  final IdClient id;
  final ChatService chat;
  final ContactsService contacts;
  final Notifications notifications;
  final PushService push;

  /// The app with these services. Integration tests pass fakes for the
  /// recorder and the file picker.
  Widget app({VoiceRecorder Function()? newRecorder, PickFile? pickFile}) => Deps(
    chat: chat,
    id: id,
    contacts: contacts,
    notifications: notifications,
    push: push,
    newRecorder: newRecorder ?? RecordVoiceRecorder.new,
    pickFile: pickFile ?? _pickWithSystemPicker,
    shareText: (text) => SharePlus.instance.share(ShareParams(text: text)),
    child: const ChamaApp(),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!onAndroid || !chat.loggedIn.value) return;
    if (state == AppLifecycleState.resumed) {
      chat.setForeground(true, pushActive: push.active.value);
      // Back on screen, maybe from the system settings or after installing
      // ntfy: the permission, the address book or the distributor may have
      // changed.
      unawaited(contacts.start());
      push.resumed();
    } else if (state == AppLifecycleState.paused) {
      chat.setForeground(false, pushActive: push.active.value);
    }
  }
}

Future<PickedFile?> _pickWithSystemPicker({required bool image}) async {
  final f = await FilePicker.pickFile(type: image ? FileType.image : FileType.any);
  if (f == null) return null;
  return PickedFile(name: f.name, bytes: await f.readAsBytes());
}
