import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Short vinyl-scratch samples played while the disc is dragged.
///
/// There are forward and backward strokes in three speeds
/// (assets/sfx/scratch_*.wav). Each one gets its own preloaded player
/// so it can start instantly.
class ScratchSound {
  ScratchSound() {
    _init();
  }

  static const _tiers = ['slow', 'mid', 'fast'];

  final Map<String, AudioPlayer> _players = {};
  bool _ready = false;
  bool _disposed = false;
  AudioPlayer? _lastPlayed;

  /// 0–1. Follows the app's volume and mute.
  double volume = 1;

  Future<void> _init() async {
    for (final dir in ['fwd', 'back']) {
      for (final tier in _tiers) {
        final p = AudioPlayer(
          // Short sound effects: don't fight the music player for audio focus.
          handleInterruptions: false,
          handleAudioSessionActivation: false,
        );
        _players['${dir}_$tier'] = p;
        try {
          await p.setAsset('assets/sfx/scratch_${dir}_$tier.wav');
        } catch (e) {
          debugPrint('Nightfall: could not load scratch sound ${dir}_$tier → $e');
        }
        if (_disposed) return;
      }
    }
    _ready = true;
  }

  /// [speed] is how fast the finger turns the disc, in radians per second.
  void play({required bool forward, required double speed}) {
    if (!_ready || _disposed || volume <= 0) return;
    final tier = speed > 14
        ? 'fast'
        : speed > 6
            ? 'mid'
            : 'slow';
    final p = _players['${forward ? 'fwd' : 'back'}_$tier'];
    if (p == null) return;

    // A new stroke cuts off the previous one, like a real record.
    final prev = _lastPlayed;
    if (prev != null && prev != p) prev.pause();
    _lastPlayed = p;

    p.setVolume(volume);
    p.seek(Duration.zero);
    p.play();
  }

  void dispose() {
    _disposed = true;
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
  }
}
