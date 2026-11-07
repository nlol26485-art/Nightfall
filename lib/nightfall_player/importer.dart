import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_info.dart';
import 'player_controller.dart';

/// Opens the phone's file picker, copies the chosen songs into the app's own
/// storage (so they're still there next time), reads each one's length and
/// quality (format, bit depth, sample rate), adds them to the library and
/// plays the first one.
Future<void> importAudioFiles(PlayerController player) async {
  await player.ready;
  final result = await FilePicker.platform.pickFiles(
    type: FileType.audio,
    allowMultiple: true,
  );
  if (result == null) return; // user cancelled
  final files = [
    for (final f in result.files)
      if (f.path != null) f,
  ];
  if (files.isEmpty) return;

  final rnd = math.Random();
  final added = <Track>[];
  final probe = AudioPlayer(handleInterruptions: false, handleAudioSessionActivation: false);
  try {
    final dir = await player.musicDirectory();
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      player.setImportStatus(
          files.length == 1 ? 'Importing ${f.name}…' : 'Importing ${i + 1} of ${files.length}…');
      try {
        final dest = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}_${_safeName(f.name)}';
        await File(f.path!).copy(dest);

        final quality = await readAudioQuality(dest);
        Duration? length;
        try {
          length = await probe.setFilePath(dest);
        } catch (e) {
          debugPrint('Nightfall: could not read length of ${f.name} → $e');
        }

        added.add(Track(
          title: f.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
          artist: 'Local Storage',
          source: dest,
          duration: length ?? Duration.zero,
          hue: 10 + rnd.nextInt(21).toDouble(), // stay in the orange range
          format: quality?.format ?? formatFromName(f.name),
          sampleRate: quality?.sampleRate,
          bitDepth: quality?.bitDepth,
        ));
      } catch (e) {
        debugPrint('Nightfall: could not import ${f.name} → $e');
      }
    }
  } finally {
    await probe.dispose();
    player.setImportStatus(null);
    try {
      await FilePicker.platform.clearTemporaryFiles(); // the picker's own cache copies
    } catch (_) {}
  }

  player.addToLibrary(added);
}

String _safeName(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
