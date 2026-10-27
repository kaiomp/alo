import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/actions.dart';
import '../common/deps.dart';
import '../common/simple_mode.dart';
import '../common/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_session.dart';
import '../services/models.dart';
import 'voice/voice_recorder.dart';

/// WhatsApp composer: a pill with emoji, text, attach and camera, and a round
/// button that is a mic while the field is empty and send once there is text.
/// The reply/edit banner sits inside the pill.
class Composer extends StatefulWidget {
  const Composer({super.key, required this.session, this.wide = false});
  final ChatSession session;
  final bool wide;

  @override
  State<Composer> createState() => ComposerState();
}

class ComposerState extends State<Composer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  Message? _replyTo;
  Message? _editing;

  VoiceRecorder? _recorder;
  DateTime? _recordingSince;
  Timer? _tick;

  /// The finger is still on the mic. Starting can outlast the hold (the
  /// first time, Android asks for the microphone).
  bool _holding = false;

  /// A recorder is asking for the mic; a second hold must not start another.
  bool _starting = false;

  /// Screen reader on: a tap on the mic started this recording, and Send or
  /// Cancel ends it (a screen reader's long press ends as soon as it starts).
  bool _locked = false;

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

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) _snack(L10n.of(context).sendFailed);
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

  Future<void> _sendPicked({required bool image}) async {
    final file = await Deps.of(context).pickFile(image: image);
    if (file == null || !mounted) return;
    final reply = _replyTo?.id;
    _clearContext();
    await _guard(
      () => image ? widget.session.sendImage(file, replyTo: reply) : widget.session.sendFile(file, replyTo: reply),
    );
  }

  Future<void> _attach(BuildContext button) async {
    final l = L10n.of(context);
    final image = await showActions<bool>(
      button,
      anchor: rectOf(button),
      actions: [
        MenuAction(true, Icons.photo_outlined, l.attachPhoto, key: const Key('attach_photo')),
        MenuAction(false, Icons.insert_drive_file_outlined, l.attachDocument, key: const Key('attach_document')),
      ],
    );
    if (image != null) await _sendPicked(image: image);
  }

  // Voice notes: hold the mic, release to send, slide left to cancel
  // (shorter than 0.5 s is dropped). [locked]: tap to start, see [_locked].
  Future<void> _startRecording({bool locked = false}) async {
    if (_recorder != null || _starting) return;
    _holding = true;
    _starting = true;
    final recorder = Deps.of(context).newRecorder();
    final bool started;
    try {
      started = await recorder.start();
    } finally {
      _starting = false;
    }
    if (!started) {
      recorder.dispose();
      if (mounted) _snack(L10n.of(context).micDenied);
      return;
    }
    if (!mounted || !_holding) {
      await recorder.cancel();
      return recorder.dispose();
    }
    setState(() {
      _recorder = recorder;
      _recordingSince = DateTime.now();
      _locked = locked;
    });
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
  }

  Future<void> _stopRecording({bool cancel = false}) async {
    _holding = false;
    final recorder = _recorder;
    final since = _recordingSince;
    _tick?.cancel();
    setState(() {
      _recorder = null;
      _recordingSince = null;
      _locked = false;
    });
    if (recorder == null || since == null) return;
    try {
      if (cancel || DateTime.now().difference(since) < const Duration(milliseconds: 500)) {
        await recorder.cancel();
        return;
      }
      final voice = await recorder.stop();
      if (voice == null) return;
      final reply = _replyTo?.id;
      _clearContext();
      await _guard(
        () => widget.session.sendVoice(
          bytes: voice.bytes,
          mimeType: voice.mimeType,
          durationMs: voice.durationMs,
          waveform: voice.waveform,
          replyTo: reply,
        ),
      );
    } finally {
      recorder.dispose();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _recorder?.cancel();
    _recorder?.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ChatColors.of(context);
    final context_ = _editing ?? _replyTo;
    final hasText = _text.text.trim().isNotEmpty;
    final since = _recordingSince;
    final iconColor = scheme.onSurfaceVariant;

    final Widget field;
    if (since != null) {
      final s = DateTime.now().difference(since).inSeconds;
      field = SizedBox(
        height: 48,
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(Icons.mic, color: scheme.error),
            const SizedBox(width: 10),
            Text(
              '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}',
              key: const Key('recording_timer'),
              style: TextStyle(fontSize: 16, fontFeatures: tabularFigures, color: scheme.onSurface),
            ),
            const SizedBox(width: 12),
            if (_locked) ...[
              const Spacer(),
              IconButton(
                key: const Key('cancel_recording'),
                tooltip: l.cancelRecording,
                icon: const Icon(Icons.delete_outline),
                color: iconColor,
                onPressed: () => _stopRecording(cancel: true),
              ),
            ] else
              Expanded(
                child: Text(
                  '‹ ${l.slideToCancel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: iconColor),
                ),
              ),
          ],
        ),
      );
    } else {
      field = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: l.emoji,
            icon: const Icon(Icons.emoji_emotions_outlined),
            color: iconColor,
            // The system keyboard has the emoji picker: bring it up.
            onPressed: _focus.requestFocus,
          ),
          Expanded(
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
                style: TextStyle(fontSize: 16, height: 22 / 16, color: scheme.onSurface),
                decoration: InputDecoration(
                  hintText: l.messageHint,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
                onChanged: (v) {
                  setState(() {});
                  if (v.isNotEmpty) widget.session.setTyping(true);
                },
              ),
            ),
          ),
          Builder(
            builder: (button) => IconButton(
              key: const Key('attach'),
              tooltip: l.attach,
              icon: const Icon(Icons.attach_file),
              color: iconColor,
              onPressed: () => _attach(button),
            ),
          ),
          if (!hasText)
            IconButton(
              key: const Key('camera'),
              tooltip: l.attachPhoto,
              icon: const Icon(Icons.photo_camera_outlined),
              color: iconColor,
              onPressed: () => _sendPicked(image: true),
            ),
          const SizedBox(width: 2),
        ],
      );
    }

    final send = hasText || _editing != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: widget.wide ? const EdgeInsets.all(12) : const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(
                  color: colors.other,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    if (colors.bubbleShadow != null)
                      BoxShadow(color: colors.bubbleShadow!, blurRadius: 0.5, offset: const Offset(0, 1)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (context_ != null && since == null)
                      _ContextBanner(
                        title: _editing != null ? l.editing : context_.senderName,
                        body: switch (context_.kind) {
                          MessageKind.image => l.photo,
                          MessageKind.voice => l.voiceMessage,
                          _ => context_.body,
                        },
                        onClose: () {
                          if (_editing != null) _text.clear();
                          _clearContext();
                        },
                      ),
                    field,
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              // From 0.6, not 0: a button at scale 0 cannot be hit, and a quick
              // tap right after typing would be lost.
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween(begin: 0.6, end: 1.0).animate(a), child: child),
              ),
              child: send
                  ? _RoundButton(
                      key: const ValueKey('send_switch'),
                      buttonKey: const Key('send'),
                      icon: _editing != null ? Icons.check : Icons.send,
                      tooltip: _editing != null ? l.saveEdit : l.send,
                      onPressed: hasText ? _send : null,
                    )
                  : _locked && since != null
                  ? _RoundButton(
                      key: const ValueKey('send_voice_switch'),
                      buttonKey: const Key('send_voice'),
                      icon: Icons.send,
                      tooltip: l.sendVoice,
                      onPressed: () => _stopRecording(),
                    )
                  : GestureDetector(
                      key: const ValueKey('mic_hold'),
                      // A screen reader's long press ends at once: the
                      // recording is dropped, and a tap records instead.
                      onLongPressStart: (_) => _startRecording(),
                      onLongPressMoveUpdate: (d) {
                        if (d.offsetFromOrigin.dx < -80) _stopRecording(cancel: true);
                      },
                      onLongPressEnd: (_) => _stopRecording(),
                      // A system dialog (the mic permission prompt), a call or
                      // the notification shade cancels the pointer: no end comes.
                      onLongPressCancel: () => _stopRecording(cancel: true),
                      // The tooltip's own long press would win the hold on
                      // touch screens: keep it to mouse hover.
                      child: TooltipTheme(
                        data: TooltipTheme.of(context).copyWith(triggerMode: TooltipTriggerMode.manual),
                        // A tap records as well, with Send and Cancel on screen:
                        // holding is a shortcut, never the only way.
                        child: _RoundButton(
                          buttonKey: const Key('mic'),
                          icon: Icons.mic,
                          tooltip: l.recordVoice,
                          size: SimpleMode.of(context) ? 60 : 48,
                          onPressed: () => _startRecording(locked: true),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 48 px orange circle with a white icon; shrinks a little while pressed.
class _RoundButton extends StatefulWidget {
  const _RoundButton({
    super.key,
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 48,
  });
  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 100),
        child: IconButton(
          key: widget.buttonKey,
          tooltip: widget.tooltip,
          onPressed: widget.onPressed,
          style: IconButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            disabledBackgroundColor: scheme.primary,
            disabledForegroundColor: scheme.onPrimary,
            fixedSize: Size.square(widget.size),
            shape: const CircleBorder(),
          ),
          icon: Icon(widget.icon, size: widget.size * 0.46),
        ),
      ),
    );
  }
}

class _ContextBanner extends StatelessWidget {
  const _ContextBanner({required this.title, required this.body, required this.onClose});
  final String title;
  final String body;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChatColors.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: colors.cardTint, borderRadius: BorderRadius.circular(18)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: colors.accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.quoteName),
                    ),
                    Text(
                      body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: colors.meta),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: theme.colorScheme.onSurfaceVariant,
              tooltip: L10n.of(context).close,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
