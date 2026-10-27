import 'package:flutter/material.dart';

import 'auth/encryption_screen.dart';
import 'auth/sign_in_screen.dart';
import 'chat_list/home_screen.dart';
import 'common/deps.dart';
import 'common/simple_mode.dart';
import 'common/theme.dart';
import 'l10n/app_localizations.dart';
import 'profile/profile_screen.dart';
import 'services/chat_service.dart';
import 'wellbeing/wellbeing_layer.dart';

/// The app. Expects a [Deps] above it (see `bootstrap` in main.dart).
class ChamaApp extends StatelessWidget {
  const ChamaApp({super.key, this.locale});

  /// Null follows the system; the demo pins Portuguese.
  final Locale? locale;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chama',
    debugShowCheckedModeBanner: false,
    theme: chamaTheme(Brightness.light),
    darkTheme: chamaTheme(Brightness.dark),
    locale: locale,
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    // pt-BR first: any locale we do not have falls back to Portuguese.
    localeResolutionCallback: (locale, supported) =>
        supported.firstWhere((s) => s.languageCode == locale?.languageCode, orElse: () => const Locale('pt')),
    builder: (context, child) {
      final deps = Deps.of(context);
      final wellbeing = deps.wellbeing;
      final simple = deps.simpleMode;
      var app = child!;
      if (wellbeing != null) app = WellbeingLayer(service: wellbeing, child: app);
      if (simple != null) app = SimpleLayer(mode: simple, child: app);
      return app;
    },
    home: const _AuthGate(),
  );
}

/// Signed out → sign-in; then encryption setup for this device (and a
/// recovery key not yet confirmed as saved); then the profile once; then the
/// chat list.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  Future<(CryptoStatus, bool, String?)>? _state;

  Future<(CryptoStatus, bool, String?)> _load(ChatService chat) async {
    final crypto = await chat.cryptoStatus();
    return (crypto, await chat.needsProfile(), await chat.pendingRecoveryKey(crypto));
  }

  @override
  Widget build(BuildContext context) {
    final chat = Deps.of(context).chat;
    return ValueListenableBuilder<bool>(
      valueListenable: chat.loggedIn,
      builder: (context, loggedIn, _) {
        if (!loggedIn) {
          _state = null;
          return const SignInScreen();
        }
        _state ??= _load(chat);
        return FutureBuilder<(CryptoStatus, bool, String?)>(
          future: _state,
          builder: (context, snap) {
            final state = snap.data;
            if (state == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            final (crypto, needsProfile, pendingKey) = state;
            if (crypto != CryptoStatus.ready || pendingKey != null) {
              return EncryptionScreen(
                status: crypto,
                recoveryKey: pendingKey,
                onDone: () => setState(() {
                  _state = Future.value((CryptoStatus.ready, needsProfile, null));
                }),
              );
            }
            if (needsProfile) {
              return ProfileScreen(
                onDone: () => setState(() {
                  _state = Future.value((CryptoStatus.ready, false, null));
                }),
              );
            }
            return const HomeScreen();
          },
        );
      },
    );
  }
}
