import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Saves the song library, playlists and likes to `library.json` in the
/// app's private storage, and keeps imported songs in a `music` folder there
/// so they survive app restarts.
class LibraryStore {
  Directory? _root;
  Future<void> _pending = Future.value();

  Future<Directory> _dir() async {
    final r = _root ?? await getApplicationDocumentsDirectory();
    _root = r;
    return r;
  }

  Future<File> _file() async => File('${(await _dir()).path}/library.json');

  /// Folder imported songs are copied into.
  Future<Directory> musicDir() async {
    final d = Directory('${(await _dir()).path}/music');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<Map<String, dynamic>?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final data = jsonDecode(await f.readAsString());
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } catch (e) {
      debugPrint('Nightfall: could not read library → $e');
      return null;
    }
  }

  /// Writes are queued so two saves never overlap, and go through a temp
  /// file so a crash mid-write can't corrupt the library.
  void save(Map<String, Object?> data) {
    final text = jsonEncode(data);
    _pending = _pending.then((_) async {
      try {
        final f = await _file();
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(text, flush: true);
        await tmp.rename(f.path);
      } catch (e) {
        debugPrint('Nightfall: could not save library → $e');
      }
    });
  }
}
