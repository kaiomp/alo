import 'package:flutter/material.dart';

import '../common/avatar.dart';
import '../common/deps.dart';
import '../common/net_image.dart';
import '../common/theme.dart';
import '../l10n/app_localizations.dart';

/// A new post for the feed: text and maybe one photo. Pops true once posted.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _text = TextEditingController();
  Uri? _image;
  bool _busy = false;

  // Limit: 500 characters, as Mastodon's default; a real server states its own.
  static const _max = 500;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final f = await Deps.of(context).pickFile(image: true);
    if (f == null || !mounted) return;
    setState(() => _image = Uri.dataFromBytes(f.bytes, mimeType: f.mimeType ?? 'image/jpeg'));
  }

  Future<void> _publish() async {
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    await Deps.of(context).social!.publish(_text.text.trim(), image: _image);
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final me = Deps.of(context).social!.me.person;
    final image = _image;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: l.close, onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        title: Text(l.newPost),
        actions: [
          ValueListenableBuilder(
            valueListenable: _text,
            builder: (context, v, _) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                key: const Key('publish'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: _busy || (v.text.trim().isEmpty && image == null) ? null : _publish,
                child: Text(l.publish),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Avatar(name: me.name, seed: me.id, mxc: me.avatar, radius: 21),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(me.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          TextField(
                            key: const Key('compose_field'),
                            controller: _text,
                            autofocus: true,
                            maxLines: null,
                            maxLength: _max,
                            textCapitalization: TextCapitalization.sentences,
                            style: const TextStyle(fontSize: 17, height: 24 / 17),
                            decoration: InputDecoration(
                              hintText: l.postHint,
                              filled: false,
                              counterText: '',
                              contentPadding: const EdgeInsets.symmetric(vertical: 6),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                          ),
                          if (image != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Stack(
                                  children: [
                                    AspectRatio(aspectRatio: 3 / 2, child: NetImage(image)),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: IconButton.filled(
                                        tooltip: l.delete,
                                        style: IconButton.styleFrom(backgroundColor: Tokens.shadeDeep),
                                        onPressed: () => setState(() => _image = null),
                                        icon: const Icon(Icons.close, size: 18, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: scheme.outlineVariant, width: 0.5)),
              ),
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('compose_photo'),
                    tooltip: l.photo,
                    color: scheme.primary,
                    onPressed: _pick,
                    icon: const Icon(Icons.image_outlined),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.public_rounded, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(l.postReach, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
