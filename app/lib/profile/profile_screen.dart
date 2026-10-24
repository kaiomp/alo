import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../common/deps.dart';
import '../l10n/app_localizations.dart';
import '../services/models.dart';

/// Name and optional photo, shown once after the first sign-in.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
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
    final photo = _photo;
    return Scaffold(
      appBar: AppBar(title: Text(l.profileTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(l.profileExplain, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Center(
                child: GestureDetector(
                  onTap: () async {
                    final f = await Deps.of(context).pickFile(image: true);
                    if (f != null) setState(() => _photo = f);
                  },
                  child: CircleAvatar(
                    radius: 56,
                    backgroundImage: photo == null ? null : MemoryImage(Uint8List.fromList(photo.bytes)),
                    child: photo == null ? const Icon(Icons.add_a_photo, size: 40) : null,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                key: const Key('profile_name'),
                controller: _name,
                autofocus: true,
                maxLength: 25,
                decoration: InputDecoration(labelText: l.yourName),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              FilledButton(key: const Key('profile_done'), onPressed: _busy ? null : _save, child: Text(l.done)),
            ],
          ),
        ),
      ),
    );
  }
}
