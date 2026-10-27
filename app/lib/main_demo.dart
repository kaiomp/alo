import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'common/brand.dart';
import 'common/deps.dart';
import 'common/net_image.dart';
import 'common/theme.dart';
import 'demo/demo_chat.dart';
import 'demo/demo_civic.dart';
import 'common/simple_mode.dart';
import 'demo/demo_data.dart';
import 'demo/demo_recorder.dart';
import 'demo/demo_services.dart';
import 'demo/demo_social.dart';
import 'demo/demo_wellbeing.dart';
import 'demo/director.dart';
import 'demo/scenes.dart';
import 'l10n/app_localizations.dart';
import 'services/models.dart';

/// The pitch demo: the real screens on fictional data, no server, already
/// signed in, with Momentos, the feed, Voz and Perfil. Web only (the photos live in
/// web/demo). `?cena=<name>` plays a scene by itself (demo/scenes.dart).
///   app/scripts/build-demo-web.sh
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.now();
  final name = Uri.base.queryParameters['cena'];
  // The first-launch question: in the simples scene, and once in the
  // clickable demo (remembered in this browser).
  final prefs = await SharedPreferences.getInstance();
  const askedKey = 'demo.simple.asked';
  final simple = SimpleMode(offered: name == null ? prefs.getBool(askedKey) ?? false : name != 'simples');
  if (name == null) simple.addListener(() => prefs.setBool(askedKey, simple.offered));
  final chat = DemoChatService(DemoWorld(now));
  final social = DemoSocialService(now, chat);
  final kit = DemoKit(
    chat: chat,
    wellbeing: DemoWellbeing(ticking: name == null),
  );
  runApp(
    Deps(
      chat: chat,
      id: DemoId(),
      contacts: DemoContacts(),
      notifications: DemoNotifications(),
      push: DemoPush(),
      social: social,
      civic: DemoCivic(now),
      wellbeing: kit.wellbeing,
      simpleMode: simple,
      newRecorder: DemoRecorder.new,
      pickFile: ({required image}) async =>
          PickedFile(name: 'feira.jpg', bytes: await demoBytes(photo('feira')), mimeType: 'image/jpeg'),
      shareText: (_) async {},
      child: _Stage(kit: kit, social: social, scene: name),
    ),
  );
}

/// The app under a brand cover until every photo is loaded; then the scene,
/// if any, plays with its tap circles on top.
class _Stage extends StatefulWidget {
  const _Stage({required this.kit, required this.social, required this.scene});
  final DemoKit kit;
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
    final social = widget.social;
    final posts = [...social.feed.value, ...social.forYou.value, ...social.postsBy(me.id)];
    final avatars = {
      for (final c in widget.kit.chat.world.chats) ...[c.avatar, for (final p in c.members) p.avatar],
      for (final p in posts) ...[p.author.avatar, p.coAuthor?.avatar],
      me.avatar,
    }.nonNulls;
    final photos = {
      for (final c in widget.kit.chat.world.chats) ...c.photos.values,
      photo('praia-nordeste'),
      photo('feira'),
    };
    final net = {
      for (final p in posts) ?p.image,
      for (final g in widget.social.moments.value) ...g.moments.map((m) => m.image),
    };
    await _pool([
      for (final u in {...avatars, ...photos})
        () async {
          final bytes = await demoBytes(u);
          if (mounted) await precacheImage(MemoryImage(bytes), context);
        },
      for (final u in net)
        () async {
          var failed = false;
          await precacheImage(NetImage.provider(u), context, onError: (_, _) => failed = true);
          if (failed) throw StateError('$u did not load');
        },
    ]);
  }

  /// Runs [tasks] four at a time, each tried up to three times: a static
  /// server can drop connections when dozens arrive at once, and a photo
  /// that still fails must not stop the scene (it loads again when shown).
  Future<void> _pool(List<Future<void> Function()> tasks) async {
    var next = 0;
    Future<void> worker() async {
      while (next < tasks.length) {
        final task = tasks[next++];
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            await task();
            break;
          } catch (e) {
            debugPrint('Demo preload: $e');
            await Future<void>.delayed(const Duration(milliseconds: 300));
          }
        }
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
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
        await scene.$2(d, widget.kit);
      } catch (e) {
        d.beat('falhou: $e');
        // ignore: avoid_print
        print('cena:fim'); // so the capture script never waits forever
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
