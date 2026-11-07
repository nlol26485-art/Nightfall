import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

import 'audio_info.dart';
import 'player_controller.dart';

/// Phone folders searched for music (and everything inside them).
const List<String> scanFolders = ['Music', 'Download', 'Downloads', 'Documents', 'Podcasts', 'Audiobooks'];
const String _phoneRoot = '/storage/emulated/0';

const Set<String> _audioExtensions = {
  'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'oga', 'opus', 'aif', 'aiff', 'aifc',
};

/// Smaller files are usually notification sounds or voice clips.
const int _minBytes = 100 * 1024;

enum ScanResult { done, noPermission, unsupported, busy }

bool _busy = false;

/// Asks for "Music and audio" access (Android 13+) or storage access (older).
Future<bool> requestMusicPermission() async {
  if (!Platform.isAndroid) return false;
  final r = await [Permission.audio, Permission.storage].request();
  return (r[Permission.audio]?.isGranted ?? false) || (r[Permission.storage]?.isGranted ?? false);
}

Future<bool> hasMusicPermission() async {
  if (!Platform.isAndroid) return false;
  return await Permission.audio.isGranted || await Permission.storage.isGranted;
}

/// Finds songs in [scanFolders] that aren't in the library yet and adds them.
/// Songs are played where they are (not copied), so they use no extra space.
/// With [askPermission] false, it quietly does nothing if access wasn't given.
Future<ScanResult> scanPhoneForMusic(PlayerController player, {bool askPermission = true}) async {
  if (!Platform.isAndroid) return ScanResult.unsupported;
  if (_busy) return ScanResult.busy;
  _busy = true;
  try {
    await player.ready;
    final ok = askPermission ? await requestMusicPermission() : await hasMusicPermission();
    if (!ok) return ScanResult.noPermission;

    player.setScanStatus('Looking for music…');
    final known = player.knownSongIds();
    final found = <String>{};
    for (final name in scanFolders) {
      final dir = Directory('$_phoneRoot/$name');
      try {
        if (!await dir.exists()) continue;
        await for (final e in dir.list(recursive: true, followLinks: false).handleError((_) {})) {
          if (e is! File) continue;
          final path = e.path;
          if (path.contains('/.') || known.contains(path) || !_isAudio(path)) continue;
          found.add(path);
        }
      } catch (e) {
        debugPrint('Nightfall: could not scan $name → $e');
      }
    }

    final rnd = math.Random();
    final songs = <Track>[];
    final list = found.toList()..sort();
    for (var i = 0; i < list.length; i++) {
      if (i % 10 == 0) player.setScanStatus('Adding ${i + 1} of ${list.length}…');
      final path = list[i];
      try {
        if (await File(path).length() < _minBytes) continue;
      } catch (_) {
        continue;
      }
      final parts = path.split('/');
      final fileName = parts.last;
      final folder = parts.length > 1 ? parts[parts.length - 2] : '';
      final quality = await readAudioQuality(path);
      songs.add(Track(
        title: fileName.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        artist: folder,
        source: path,
        hue: 10 + rnd.nextInt(21).toDouble(),
        format: quality?.format ?? formatFromName(fileName),
        sampleRate: quality?.sampleRate,
        bitDepth: quality?.bitDepth,
      ));
    }

    player.addScanned(songs);
    player.setScanStatus(null);
    await _readLengths(player, songs);
    return ScanResult.done;
  } catch (e) {
    debugPrint('Nightfall: scan failed → $e');
    return ScanResult.done;
  } finally {
    if (player.scanning) player.setScanStatus(null);
    _busy = false;
  }
}

bool _isAudio(String path) {
  final dot = path.lastIndexOf('.');
  return dot > 0 && _audioExtensions.contains(path.substring(dot + 1).toLowerCase());
}

/// Fills in song lengths in the background, a few at a time.
Future<void> _readLengths(PlayerController player, List<Track> songs) async {
  if (songs.isEmpty) return;
  final probe = AudioPlayer(handleInterruptions: false, handleAudioSessionActivation: false);
  final batch = <Track>[];
  try {
    for (final t in songs) {
      try {
        final d = await probe.setFilePath(t.source!);
        if (d != null && d > Duration.zero) batch.add(t.withDuration(d));
      } catch (_) {}
      if (batch.length >= 20) {
        player.updateTracks(List.of(batch));
        batch.clear();
      }
    }
    player.updateTracks(batch);
  } finally {
    await probe.dispose();
  }
}
