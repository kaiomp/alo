import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'deps.dart';
import 'theme.dart';

/// Yellow "Conectando…" strip while sync is failing (spec section 9).
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: Deps.of(context).chat.connected,
    builder: (context, connected, _) => connected
        ? const SizedBox.shrink()
        : Container(
            width: double.infinity,
            color: ChatColors.of(context).banner,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: Text(
              L10n.of(context).connecting,
              key: const Key('connecting_banner'),
              style: TextStyle(color: ChatColors.of(context).onBanner),
            ),
          ),
  );
}
