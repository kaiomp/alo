import 'package:flutter/material.dart';

import 'app.dart';
import 'chat/voice/voice_recorder.dart';
import 'common/brand.dart';
import 'common/deps.dart';
import 'common/net_image.dart';
import 'common/theme.dart';
import 'demo/demo_chat.dart';
import 'demo/demo_data.dart';
import 'demo/demo_services.dart';
import 'demo/demo_social.dart';
import 'demo/director.dart';
import 'demo/scenes.dart';
import 'l10n/app_localizations.dart';
import 'services/models.dart';

/// The pitch demo: the real screens on fictional data, no server, already
/// signed in, with Momentos, Praça and Perfil. Web only (the photos live in
/// web/demo). `?cena=<name>` plays a scene by itself (demo/scenes.dart).
///   flutter build web -t lib/main_demo.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.now();
  final chat = DemoChatService(DemoWorld(now));
  final social = DemoSocialService(now, chat);
  final name = Uri.base.queryParameters['cena'];
  runApp(
    Deps(
      chat: chat,
      id: DemoId(),
      contacts: DemoContacts(),
      notifications: DemoNotifications(),
      push: DemoPush(),
      social: social,
      newRecorder: RecordVoiceRecorder.new,
      pickFile: ({required image}) async =>
          PickedFile(name: 'feira.jpg', bytes: await demoBytes(photo('feira')), mimeType: 'image/jpeg'),
      shareText: (_) async {},
      child: _Stage(chat: chat, social: social, scene: name),
    ),
  );
}

/// The app under a brand cover until every photo is loaded; then the scene,
/// if any, plays with its tap circles on top.
class _Stage extends StatefulWidget {
  const _Stage({required this.chat, required this.social, required this.scene});
  final DemoChatService chat;
  final DemoSocialService social;
  final String? scene;

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  late final _director = widget.scene == null ? null : Director(widget.scene!);
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _preload() async {
    final avatars = {
      for (final c in widget.chat.world.chats) ...[c.avatar, for (final p in c.members) p.avatar],
      me.avatar,
    }.nonNulls;
    final photos = {
      for (final c in widget.chat.world.chats) ...c.photos.values,
      photo('praia-nordeste'),
      photo('feira'),
    };
    final net = {
      for (final p in [...widget.social.feed.value, ...widget.social.postsBy(me.id)]) ?p.image,
      for (final g in widget.social.moments.value) ...g.moments.map((m) => m.image),
    };
    await Future.wait([
      for (final u in {...avatars, ...photos})
        demoBytes(u).then((b) => mounted ? precacheImage(MemoryImage(b), context) : null),
      for (final u in net) precacheImage(NetImage.provider(u), context),
    ]);
  }

  Future<void> _run() async {
    await _preload();
    final d = _director;
    final scene = d == null ? null : scenes[d.name];
    if (d != null && scene != null) {
      await scene.$1?.call(d);
      // Let the first screen settle under the cover.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      d.taps.value = null;
    }
    if (!mounted) return;
    setState(() => _ready = true);
    if (d == null || scene == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      d.start();
      try {
        await scene.$2(d, widget.chat);
      } catch (e) {
        d.beat('falhou: $e');
      }
      d.end();
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _director;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          const ChamaApp(locale: Locale('pt')),
          if (d != null) Positioned.fill(child: TapOverlay(taps: d.taps)),
          if (!_ready)
            Positioned.fill(
              child: IgnorePointer(
                child: Localizations(
                  locale: const Locale('pt'),
                  delegates: L10n.localizationsDelegates,
                  child: const ColoredBox(
                    color: Tokens.cream,
                    child: Center(child: ChamaMark(size: 72, tile: true)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
