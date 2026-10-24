import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../auth/onboarding.dart';
import '../common/deps.dart';
import '../common/theme.dart';
import '../common/widgets.dart';
import '../l10n/app_localizations.dart';
import '../services/models.dart';

/// Name and optional photo: once after the first sign-in ([editing] false),
/// and from the settings ([editing] true, with the current name).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.onDone, this.editing = false, this.initialName = ''});
  final VoidCallback onDone;
  final bool editing;
  final String initialName;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _name = TextEditingController(text: widget.initialName);
  PickedFile? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await Deps.of(context).chat.saveProfile(name: name, photo: _photo);
      widget.onDone();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L10n.of(context).errUnknown)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final photo = _photo;
    final picker = Center(
      child: Material(
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        color: scheme.surfaceContainer,
        child: InkWell(
          onTap: () async {
            final f = await Deps.of(context).pickFile(image: true);
            if (f != null) setState(() => _photo = f);
          },
          child: Ink(
            width: 112,
            height: 112,
            decoration: photo == null
                ? null
                : BoxDecoration(
                    image: DecorationImage(image: MemoryImage(Uint8List.fromList(photo.bytes)), fit: BoxFit.cover),
                  ),
            child: photo == null
                ? Icon(Icons.add_a_photo_outlined, size: 36, color: ChatColors.of(context).accent)
                : null,
          ),
        ),
      ),
    );
    final name = TextField(
      key: const Key('profile_name'),
      controller: _name,
      autofocus: !widget.editing,
      maxLength: 25,
      buildCounter: counterNearLimit,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(labelText: l.yourName),
      onSubmitted: (_) => _save(),
    );
    final done = FilledButton(key: const Key('profile_done'), onPressed: _busy ? null : _save, child: Text(l.done));
    if (!widget.editing) {
      return OnboardingScaffold(
        cta: done,
        children: [
          OnboardingTitle(title: l.profileTitle, body: l.profileExplain),
          picker,
          const SizedBox(height: 24),
          name,
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.profileTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [picker, const SizedBox(height: 24), name, const SizedBox(height: 16), done],
          ),
        ),
      ),
    );
  }
}
