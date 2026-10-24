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
import 'config.dart';
import 'contacts/address_book.dart';
import 'contacts/contacts_service.dart';
import 'services/chat_service.dart';
import 'services/models.dart';

/// Everything the app runs, started once per process.
class AppServices with WidgetsBindingObserver {
  AppServices._(this.id, this.chat, this.contacts) {
    WidgetsBinding.instance.addObserver(this);
  }

  static Future<AppServices> start() async {
    if (!kIsWeb) unawaited(getTemporaryDirectory().then(sweepVoiceFiles));
    final id = IdClient(chamaBaseUrl);
    final chat = await ChatService.start(homeserver: chamaBaseUrl, id: id);
    final prefs = await SharedPreferences.getInstance();
    final contacts = ContactsService(chat, onAndroid ? DeviceAddressBook() : NoAddressBook(), prefs);
    return AppServices._(id, chat, contacts);
  }

  final IdClient id;
  final ChatService chat;
  final ContactsService contacts;

  /// The app with these services. Integration tests pass fakes for the
  /// recorder and the file picker.
  Widget app({VoiceRecorder Function()? newRecorder, PickFile? pickFile}) => Deps(
    chat: chat,
    id: id,
    contacts: contacts,
    newRecorder: newRecorder ?? RecordVoiceRecorder.new,
    pickFile: pickFile ?? _pickWithSystemPicker,
    shareText: (text) => SharePlus.instance.share(ShareParams(text: text)),
    child: const ChamaApp(),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!onAndroid || !chat.loggedIn.value) return;
    // Back on screen, maybe from the system settings: the permission or the
    // address book may have changed.
    if (state == AppLifecycleState.resumed) unawaited(contacts.start());
  }
}

Future<PickedFile?> _pickWithSystemPicker({required bool image}) async {
  final f = await FilePicker.pickFile(type: image ? FileType.image : FileType.any);
  if (f == null) return null;
  return PickedFile(name: f.name, bytes: await f.readAsBytes());
}
