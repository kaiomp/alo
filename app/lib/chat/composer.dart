import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/chat_session.dart';
import '../services/models.dart';

/// Text field and send button, with a reply/edit banner above it.
/// The media task adds the attach button and the hold-to-record mic.
class Composer extends StatefulWidget {
  const Composer({super.key, required this.session});
  final ChatSession session;

  @override
  State<Composer> createState() => ComposerState();
}

class ComposerState extends State<Composer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  Message? _replyTo;
  Message? _editing;

  void replyTo(Message m) {
    setState(() {
      _editing = null;
      _replyTo = m;
    });
    _focus.requestFocus();
  }

  void edit(Message m) {
    setState(() {
      _replyTo = null;
      _editing = m;
      _text.text = m.body;
    });
    _focus.requestFocus();
  }

  void _clearContext() => setState(() {
    _replyTo = null;
    _editing = null;
  });

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L10n.of(context).sendFailed)));
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final reply = _replyTo?.id;
    final edit = _editing?.id;
    _text.clear();
    _clearContext();
    await _guard(() => widget.session.sendText(text, replyTo: reply, editOf: edit));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final context_ = _editing ?? _replyTo;
    final hasText = _text.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(24)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (context_ != null)
                      ListTile(
                        dense: true,
                        leading: Icon(_editing != null ? Icons.edit : Icons.reply),
                        title: Text(_editing != null ? l.editing : context_.senderName),
                        subtitle: Text(context_.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            if (_editing != null) _text.clear();
                            _clearContext();
                          },
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: CallbackShortcuts(
                        // Wide screens: Enter sends, Shift+Enter breaks the line (WhatsApp Web).
                        bindings: {if (kIsWeb) const SingleActivator(LogicalKeyboardKey.enter): _send},
                        child: TextField(
                          key: const Key('composer_text'),
                          controller: _text,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 6,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(hintText: l.messageHint, border: InputBorder.none),
                          onChanged: (v) {
                            setState(() {});
                            if (v.isNotEmpty) widget.session.setTyping(true);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            FloatingActionButton.small(
              key: const Key('send'),
              heroTag: null,
              onPressed: hasText ? _send : null,
              child: Icon(_editing != null ? Icons.check : Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
