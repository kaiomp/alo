import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../common/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../services/models.dart';
import 'waveform.dart';

/// Play button, waveform and duration for a voice note. Downloads and
/// decrypts on first play (FluffyChat lib/pages/chat/events/audio_player.dart:
/// temp file on native, data URI on web). The bubble draws the time and
/// ticks at the bottom right, level with the duration.
class VoicePlayer extends StatefulWidget {
  const VoicePlayer({super.key, required this.message, required this.load, required this.color});

  final Message message;
  final Future<Uint8List> Function() load;

  /// Played part of the waveform.
  final Color color;

  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _state;
  bool _loading = false;

  /// Native: the decrypted copy the player reads. Deleted with the player so
  /// no plaintext voice note stays in the temp folder.
  File? _file;

  void _failed() {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L10n.of(context).downloadFailed)));
  }

  /// Not awaited: play() completes only when playback stops.
  void _play(AudioPlayer player) => unawaited(
    player.play().catchError((Object e) {
      debugPrint('Voice note playback failed: $e');
      _failed();
    }),
  );

  Future<void> _toggle() async {
    final existing = _player;
    if (existing != null) {
      existing.playing ? await existing.pause() : _play(existing);
      return;
    }
    setState(() => _loading = true);
    final player = AudioPlayer();
    try {
      final bytes = await widget.load();
      final m = widget.message;
      if (kIsWeb) {
        await player.setAudioSource(AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: m.mimeType ?? 'audio/ogg')));
      } else {
        // Only the extension comes from the sender's file name: the name
        // itself could point outside the temp folder.
        final dir = (await getTemporaryDirectory()).path;
        final file = _file = File(p.join(dir, 'voz_${m.id.hashCode.toUnsigned(32)}${p.extension(m.body)}'));
        await file.writeAsBytes(bytes);
        await player.setFilePath(file.path);
      }
      if (!mounted) {
        _file?.delete().ignore();
        return await player.dispose();
      }
      _state = player.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          player
            ..pause()
            ..seek(Duration.zero);
        }
        if (mounted) setState(() {});
      });
      setState(() => _player = player);
      _play(player);
    } catch (e) {
      debugPrint('Voice note load failed: $e');
      await player.dispose();
      _failed();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _state?.cancel();
    _player?.dispose();
    _file?.delete().ignore();
    super.dispose();
  }

  static String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final player = _player;
    final m = widget.message;
    final total = Duration(milliseconds: m.durationMs ?? 0);
    final metaStyle = DefaultTextStyle.of(context).style
        .merge(TextStyle(fontSize: 11, height: 16 / 11, color: colors.meta, fontFeatures: tabularFigures));
    return SizedBox(
      width: 240,
      child: Row(
        children: [
          SizedBox.square(
            dimension: 40,
            child: _loading
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2, color: colors.meta),
                  )
                : IconButton(
                    key: Key('voice_play_${m.id}'),
                    padding: EdgeInsets.zero,
                    iconSize: 32,
                    color: colors.meta,
                    onPressed: _toggle,
                    icon: Icon(player?.playing == true ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: StreamBuilder<Duration>(
              stream: player?.positionStream,
              builder: (context, snap) {
                final pos = snap.data ?? Duration.zero;
                final length = player?.duration ?? total;
                final progress = length.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / length.inMilliseconds;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    CustomPaint(
                      size: const Size(double.infinity, 24),
                      painter: WaveformPainter(waveformBars(m.waveform), progress, widget.color, colors.meta),
                    ),
                    const SizedBox(height: 2),
                    Text(_fmt(player == null || pos == Duration.zero ? length : pos), style: metaStyle),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Bars in 0..1 drawn as rounded columns; the first [progress] of them in
/// [color], the rest in [rest] at reduced opacity.
class WaveformPainter extends CustomPainter {
  WaveformPainter(this.bars, this.progress, this.color, [Color? rest]) : rest = rest ?? color;
  final List<double> bars;
  final double progress;
  final Color color;
  final Color rest;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / bars.length;
    for (var i = 0; i < bars.length; i++) {
      final played = i / bars.length < progress;
      final h = (bars[i] * size.height).clamp(3.0, size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * w + w * 0.2, (size.height - h) / 2, w * 0.6, h),
          const Radius.circular(2),
        ),
        Paint()..color = played ? color : rest.withValues(alpha: 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.progress != progress || old.bars != bars || old.color != color || old.rest != rest;
}
