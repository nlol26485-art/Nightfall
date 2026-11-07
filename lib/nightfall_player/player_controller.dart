import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'library_store.dart';
import 'scratch_sound.dart';
import 'settings.dart';

/// One song.
class Track {
  const Track({
    required this.title,
    required this.artist,
    this.source,
    this.duration = Duration.zero,
    this.hue = 18,
    this.format,
    this.sampleRate,
    this.bitDepth,
  });

  final String title;
  final String artist;

  /// Where the audio comes from:
  ///  * `https://...`  → streamed
  ///  * `assets/...`   → bundled asset (list it in pubspec.yaml)
  ///  * anything else  → treated as a file path on the device
  ///  * `null`         → no audio (the "No songs yet" placeholder)
  final String? source;

  /// Shown until real audio reports its length.
  final Duration duration;

  /// Hue (0–360) of the disc label. Keep it 10–30 to stay in the orange scheme.
  final double hue;

  /// 'FLAC', 'WAV', 'AIFF', 'ALAC', 'MP3', 'AAC', 'OGG'...
  final String? format;

  /// Hz, e.g. 96000. Only known for lossless files.
  final int? sampleRate;

  /// Bits per sample, e.g. 24. Only known for lossless files.
  final int? bitDepth;

  /// Stable id used by playlists and likes.
  String get id => source ?? title;

  bool get isLossless => const {'FLAC', 'WAV', 'AIFF', 'ALAC'}.contains(format);

  /// Better than CD quality: 24-bit and/or above 48 kHz.
  bool get isHiRes => isLossless && ((bitDepth ?? 0) >= 24 || (sampleRate ?? 0) > 48000);

  /// Text for the small badge, or null for lossy files.
  String? get badge => isHiRes ? 'HI-RES' : (isLossless ? 'LOSSLESS' : null);

  /// e.g. "FLAC · 24-bit · 96 kHz".
  String? get qualityText {
    final rate = sampleRate;
    final parts = <String>[
      if (format != null) format!,
      if (bitDepth != null && bitDepth! > 0) '$bitDepth-bit',
      if (rate != null && rate > 0) _khz(rate),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _khz(int hz) {
    final k = hz / 1000;
    return k == k.roundToDouble() ? '${k.round()} kHz' : '${k.toStringAsFixed(1)} kHz';
  }

  Track withDuration(Duration d) => Track(
        title: title,
        artist: artist,
        source: source,
        duration: d,
        hue: hue,
        format: format,
        sampleRate: sampleRate,
        bitDepth: bitDepth,
      );

  Map<String, Object?> toJson() => {
        'title': title,
        'artist': artist,
        'source': source,
        'ms': duration.inMilliseconds,
        'hue': hue,
        'format': format,
        'rate': sampleRate,
        'bits': bitDepth,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        title: j['title'] as String? ?? 'Unknown',
        artist: j['artist'] as String? ?? '',
        source: j['source'] as String?,
        duration: Duration(milliseconds: (j['ms'] as num?)?.toInt() ?? 0),
        hue: (j['hue'] as num?)?.toDouble() ?? 18,
        format: j['format'] as String?,
        sampleRate: (j['rate'] as num?)?.toInt(),
        bitDepth: (j['bits'] as num?)?.toInt(),
      );
}

/// A named list of songs (stored as song ids).
class Playlist {
  Playlist({required this.id, required this.name, List<String>? songIds}) : songIds = songIds ?? [];

  final String id;
  String name;
  final List<String> songIds;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'songs': songIds};

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Playlist',
        songIds: [for (final s in (j['songs'] as List? ?? const [])) if (s is String) s],
      );
}

/// Owns the library, playlists, playback state, the audio engine and the
/// disc's spin. Both screens listen to one instance of this.
class PlayerController extends ChangeNotifier {
  PlayerController() {
    _subs
      ..add(_audio.positionStream.listen((p) {
        if (!_scrubbing && current.source != null) {
          final heard = p - _position;
          if (_playing && heard > Duration.zero && heard < const Duration(seconds: 2)) _countListening(heard);
          _position = p;
          notifyListeners();
        }
      }))
      ..add(_audio.durationStream.listen((d) {
        _realDuration = d;
        // Remember the real length so the lists show it too.
        if (d != null && d > Duration.zero && current.source != null && current.duration != d) {
          updateTrack(current.withDuration(d));
        }
        notifyListeners();
      }))
      ..add(_audio.processingStateStream.listen((s) {
        if (s == ProcessingState.completed) _onTrackEnd();
      }));
    _audio.setVolume(_volume);
    _scratch.volume = _volume;
    ready = _restore();
  }

  /// Shown on the disc and titles while nothing is queued.
  static const Track emptyTrack = Track(title: 'No songs yet', artist: 'Tap + to add music');

  /// Degrees per second the disc turns while playing (~33⅓ rpm).
  static const double spinDegreesPerSecond = 200;

  final AndroidEqualizer _eq = AndroidEqualizer();
  final AndroidLoudnessEnhancer _boost = AndroidLoudnessEnhancer();
  late final AudioPlayer _audio = AudioPlayer(
    audioPipeline: AudioPipeline(androidAudioEffects: [_eq, _boost]),
  );
  final List<StreamSubscription<dynamic>> _subs = [];
  final LibraryStore _store = LibraryStore();
  final math.Random _rnd = math.Random();

  /// Read these freely; change them through the controller's methods.
  final AppSettings settings = AppSettings();
  final ListeningStats stats = ListeningStats();

  /// Completes once the saved library has been loaded.
  late final Future<void> ready;

  final List<Track> _library = []; // every imported song
  final List<Playlist> _playlists = [];
  final Set<String> _liked = {}; // song ids
  final Set<String> _hidden = {}; // phone songs the user deleted, so scans skip them
  String? _musicDirPath;

  List<Track> _tracks = []; // the play queue: all songs or one playlist
  String? _queuePlaylistId; // null = queue is "all songs"

  int _index = 0;
  int _loadId = 0;
  bool _playing = false;
  bool _scrubbing = false;
  bool _resumeAfterScrub = false;
  Duration _position = Duration.zero;
  Duration? _realDuration;
  double _volume = .8;
  bool _muted = false;
  String? _importStatus;
  String? _scanStatus;
  Duration _heardThisPlay = Duration.zero;
  bool _countedThisPlay = false;
  DateTime _lastStatsSave = DateTime.now();

  // ---------------------------------------------------------------- getters
  /// The play queue.
  List<Track> get tracks => List.unmodifiable(_tracks);
  List<Track> get library => List.unmodifiable(_library);
  List<Playlist> get playlists => List.unmodifiable(_playlists);

  /// Id of the playlist being played, or null when playing from all songs.
  String? get queuePlaylistId => _queuePlaylistId;

  int get index => _index;
  bool get isEmpty => _tracks.isEmpty;
  Track get current => _tracks.isEmpty ? emptyTrack : _tracks[_index];
  bool isCurrent(Track t) => _tracks.isNotEmpty && current.id == t.id;
  bool get playing => _playing;
  bool get scrubbing => _scrubbing;
  bool get isLiked => _tracks.isNotEmpty && _liked.contains(current.id);
  double get volume => _volume;
  bool get muted => _muted || _volume == 0;
  Duration get position => _position;
  Duration get duration =>
      current.source != null ? (_realDuration ?? current.duration) : current.duration;
  double get progress {
    final d = duration.inMilliseconds;
    return d == 0 ? 0 : (_position.inMilliseconds / d).clamp(0.0, 1.0).toDouble();
  }

  /// e.g. "Importing 2 of 5…" while songs are being copied in, else null.
  String? get importStatus => _importStatus;

  /// Exposes the underlying player if you need volume, speed, etc.
  AudioPlayer get audioPlayer => _audio;

  // --------------------------------------------------------------- playback
  void play() {
    if (_tracks.isEmpty) return;
    _playing = true;
    if (current.source != null) _audio.play();
    notifyListeners();
  }

  void pause() {
    _playing = false;
    _audio.pause();
    _save(); // keep listening stats
    notifyListeners();
  }

  void toggle() => _playing ? pause() : play();

  void next({bool autoplay = false}) {
    if (_tracks.isEmpty) return;
    var i = _index + 1;
    if (settings.shuffle && _tracks.length > 1) {
      do {
        i = _rnd.nextInt(_tracks.length);
      } while (i == _index);
    }
    select(i, autoplay: autoplay || _playing);
  }

  void previous() {
    if (_tracks.isEmpty) return;
    if (_position > const Duration(seconds: 3)) {
      seek(Duration.zero);
    } else {
      select(_index - 1, autoplay: _playing);
    }
  }

  /// Plays song [i] of the current queue.
  void select(int i, {bool autoplay = true}) {
    if (_tracks.isEmpty) return;
    _index = i % _tracks.length;
    _load(play: autoplay);
  }

  /// Makes [list] the queue and plays song [i] from it.
  /// Pass [playlistId] when the list is a playlist.
  void playFrom(List<Track> list, int i, {String? playlistId}) {
    if (list.isEmpty) return;
    _tracks = List.of(list);
    _queuePlaylistId = playlistId;
    select(i);
  }

  void seek(Duration p) {
    _position = _clamp(p);
    if (current.source != null) _audio.seek(_position);
    notifyListeners();
  }

  void seekFraction(double f) => seek(duration * f.clamp(0.0, 1.0));

  void toggleLike() {
    if (_tracks.isEmpty) return;
    final id = current.id;
    _liked.contains(id) ? _liked.remove(id) : _liked.add(id);
    _save();
    notifyListeners();
  }

  // ----------------------------------------------------------------- volume
  void setVolume(double v) {
    _volume = v.clamp(0.0, 1.0).toDouble();
    _muted = false;
    _audio.setVolume(_volume);
    _scratch.volume = _volume;
    notifyListeners();
  }

  void toggleMute() {
    _muted = !_muted;
    _audio.setVolume(_muted ? 0 : _volume);
    _scratch.volume = _muted ? 0 : _volume;
    notifyListeners();
  }

  // ---------------------------------------------------------------- library
  /// Folder that imported songs are copied into.
  Future<Directory> musicDirectory() => _store.musicDir();

  void setImportStatus(String? status) {
    _importStatus = status;
    notifyListeners();
  }

  /// Adds imported songs to the library. With [playFirst], plays the first
  /// new song with all songs as the queue.
  void addToLibrary(List<Track> songs, {bool playFirst = true}) {
    if (songs.isEmpty) return;
    final firstNew = _library.length;
    _library.addAll(songs);
    _save();
    if (playFirst) {
      playFrom(_library, firstNew);
    } else if (_queuePlaylistId == null) {
      _tracks.addAll(songs);
      if (_tracks.length == songs.length) {
        select(0, autoplay: false);
      } else {
        notifyListeners();
      }
    } else {
      notifyListeners();
    }
  }

  /// Swaps a song for an updated copy everywhere (matched by id).
  void updateTrack(Track t) => updateTracks([t]);

  void updateTracks(List<Track> updated) {
    if (updated.isEmpty) return;
    final byId = {for (final t in updated) t.id: t};
    for (var i = 0; i < _library.length; i++) {
      final u = byId[_library[i].id];
      if (u != null) _library[i] = u;
    }
    for (var i = 0; i < _tracks.length; i++) {
      final u = byId[_tracks[i].id];
      if (u != null) _tracks[i] = u;
    }
    _save();
    notifyListeners();
  }

  /// True for songs imported with + (the app keeps its own copy);
  /// false for songs found on the phone by a scan (played in place).
  bool isAppCopy(Track t) {
    final dir = _musicDirPath;
    final src = t.source;
    return dir != null && src != null && src.startsWith(dir);
  }

  // ---------------------------------------------------------- phone scan
  /// e.g. "Looking for music…" while a scan runs, else null.
  String? get scanStatus => _scanStatus;
  bool get scanning => _scanStatus != null;
  DateTime? lastScan;
  int? lastScanAdded;

  /// Songs found on the phone that the user removed.
  int get hiddenCount => _hidden.length;

  void setScanStatus(String? status) {
    _scanStatus = status;
    notifyListeners();
  }

  /// Ids a scan should skip: already in the library, or hidden by the user.
  Set<String> knownSongIds() => {for (final t in _library) t.id, ..._hidden};

  /// Adds songs a scan found, without interrupting what's playing.
  void addScanned(List<Track> songs) {
    lastScan = DateTime.now();
    lastScanAdded = songs.length;
    if (songs.isEmpty) {
      notifyListeners();
    } else {
      addToLibrary(songs, playFirst: false);
    }
  }

  void unhideAll() {
    _hidden.clear();
    _save();
    notifyListeners();
  }

  /// Removes a song from the app completely (library, playlists, queue) and
  /// deletes the app's copy of the file. The original on the phone is kept.
  Future<void> removeFromLibrary(Track t) async {
    _library.removeWhere((x) => x.id == t.id);
    for (final p in _playlists) {
      p.songIds.remove(t.id);
    }
    _liked.remove(t.id);
    stats.forget(t.id);
    _removeFromQueue(t.id);
    if (!isAppCopy(t)) _hidden.add(t.id); // a song found on the phone: just stop showing it
    _save();
    notifyListeners();

    final src = t.source;
    if (src != null && isAppCopy(t)) {
      try {
        final f = File(src);
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('Nightfall: could not delete $src → $e');
      }
    }
  }

  // -------------------------------------------------------------- playlists
  Playlist? playlistById(String id) {
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The songs of [p], in order.
  List<Track> tracksOf(Playlist p) {
    final byId = {for (final t in _library) t.id: t};
    return [
      for (final id in p.songIds)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  Playlist createPlaylist(String name) {
    final p = Playlist(id: DateTime.now().microsecondsSinceEpoch.toString(), name: _cleanName(name));
    _playlists.add(p);
    _save();
    notifyListeners();
    return p;
  }

  void renamePlaylist(String id, String name) {
    final p = playlistById(id);
    if (p == null) return;
    p.name = _cleanName(name);
    _save();
    notifyListeners();
  }

  /// Deletes the playlist only; its songs stay in the library.
  void deletePlaylist(String id) {
    _playlists.removeWhere((p) => p.id == id);
    if (_queuePlaylistId == id) _queuePlaylistId = null;
    _save();
    notifyListeners();
  }

  /// Adds songs that aren't in the playlist yet. Returns how many were added.
  int addToPlaylist(String id, Iterable<Track> songs) {
    final p = playlistById(id);
    if (p == null) return 0;
    var added = 0;
    for (final t in songs) {
      if (p.songIds.contains(t.id)) continue;
      p.songIds.add(t.id);
      added++;
      if (_queuePlaylistId == id) _tracks.add(t); // it's playing: extend the queue
    }
    if (added == 0) return 0;
    _save();
    if (_queuePlaylistId == id && _tracks.length == added) {
      select(0, autoplay: false); // queue was empty
    } else {
      notifyListeners();
    }
    return added;
  }

  void removeFromPlaylist(String id, Track t) {
    final p = playlistById(id);
    if (p == null) return;
    p.songIds.remove(t.id);
    if (_queuePlaylistId == id) _removeFromQueue(t.id);
    _save();
    notifyListeners();
  }

  String _cleanName(String name) {
    final n = name.trim();
    return n.isEmpty ? 'New playlist' : n;
  }

  // --------------------------------------------------------------- settings
  /// Change settings, e.g. `c.updateSettings((s) => s.haptics = false)`.
  void updateSettings(void Function(AppSettings s) change) {
    change(settings);
    _save();
    notifyListeners();
  }

  void toggleShuffle() => updateSettings((s) => s.shuffle = !s.shuffle);

  /// Off → All → One → Off.
  void cycleRepeat() => updateSettings((s) => s.repeat = RepeatSetting.values[(s.repeat.index + 1) % 3]);

  // -------------------------------------------------------------- equalizer
  /// The phone's equalizer bands, or null if it isn't available yet
  /// (it starts once the first song is loaded) or not on Android.
  Future<AndroidEqualizerParameters?> equalizerParameters() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _eq.parameters.timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  Future<void> setEqEnabled(bool on) async {
    settings.eqEnabled = on;
    _save();
    notifyListeners();
    await _eq.setEnabled(on);
  }

  /// Saves the band's gain (call when a slider is let go).
  Future<void> setEqGain(int band, double db) async {
    final p = await equalizerParameters();
    if (p == null || band < 0 || band >= p.bands.length) return;
    await p.bands[band].setGain(db);
    settings.eqGains = [for (final b in p.bands) b.gain];
    settings.eqPreset = 'Custom';
    _save();
    notifyListeners();
  }

  Future<void> applyEqPreset(String name) async {
    final p = await equalizerParameters();
    if (p == null) return;
    for (final b in p.bands) {
      final g = eqPresetGain(name, b.centerFrequency).clamp(p.minDecibels, p.maxDecibels).toDouble();
      await b.setGain(g);
    }
    settings.eqGains = [for (final b in p.bands) b.gain];
    settings.eqPreset = name;
    if (!settings.eqEnabled) await setEqEnabled(true);
    _save();
    notifyListeners();
  }

  /// Extra loudness in dB (0 = off).
  Future<void> setBoost(double db) async {
    settings.boostDb = db;
    _save();
    notifyListeners();
    await _boost.setTargetGain(db);
    await _boost.setEnabled(db > 0);
  }

  void _applySavedEffects() {
    _eq.setEnabled(settings.eqEnabled);
    _boost.setTargetGain(settings.boostDb);
    _boost.setEnabled(settings.boostDb > 0);
    // Band gains can only be set once the phone's equalizer is ready.
    _eq.parameters.then((p) async {
      final gains = settings.eqGains;
      for (var i = 0; i < p.bands.length && i < gains.length; i++) {
        await p.bands[i].setGain(gains[i].clamp(p.minDecibels, p.maxDecibels).toDouble());
      }
    });
  }

  // ------------------------------------------------------------ sleep timer
  Timer? _sleepTimer;
  DateTime? _sleepAt;
  bool _sleepAtEnd = false;

  /// When music will pause, or null.
  DateTime? get sleepAt => _sleepAt;
  bool get sleepAtEndOfSong => _sleepAtEnd;

  /// Pause after [after], or at the end of the current song. Pass nothing to cancel.
  void setSleepTimer({Duration? after, bool endOfSong = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAt = null;
    _sleepAtEnd = endOfSong;
    if (after != null) {
      _sleepAt = DateTime.now().add(after);
      _sleepTimer = Timer(after, () {
        _sleepTimer = null;
        _sleepAt = null;
        pause();
      });
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- stats
  void resetStats() {
    stats.clear();
    _save();
    notifyListeners();
  }

  void _countListening(Duration heard) {
    final ms = heard.inMilliseconds;
    final s = stats.song(current.id);
    stats.totalMs += ms;
    s.ms += ms;
    _heardThisPlay += heard;
    final d = duration;
    final needed = d > Duration.zero && d < const Duration(minutes: 1) ? d * .5 : const Duration(seconds: 30);
    final now = DateTime.now();
    if (!_countedThisPlay && _heardThisPlay >= needed) {
      _countedThisPlay = true;
      s.plays++;
      s.last = now.millisecondsSinceEpoch;
      stats.markRecent(current.id);
      _lastStatsSave = now;
      _save();
    } else if (now.difference(_lastStatsSave) > const Duration(seconds: 30)) {
      _lastStatsSave = now;
      _save();
    }
  }

  void _onTrackEnd() {
    if (_sleepAtEnd) {
      _sleepAtEnd = false;
      seek(Duration.zero);
      pause();
      return;
    }
    if (settings.repeat == RepeatSetting.one) {
      _heardThisPlay = Duration.zero;
      _countedThisPlay = false;
      seek(Duration.zero);
      _audio.play();
      return;
    }
    final last = _index == _tracks.length - 1;
    if (settings.repeat == RepeatSetting.off && !settings.shuffle && last) {
      select(0, autoplay: false); // stop at the end of the queue
      return;
    }
    next(autoplay: true);
  }

  // ------------------------------------------------------- disc scrubbing
  void beginScrub() {
    _scrubbing = true;
    _discSpeed = 0;
    _scratchDir = 0;
    _scratchTravel = 0;
    _scratchSpeed = 0;
    _lastScratchMove = null;
    _resumeAfterScrub = _playing && current.source != null;
    if (_resumeAfterScrub) _audio.pause();
    notifyListeners();
  }

  void scrubBy(Duration delta) {
    if (_tracks.isEmpty) return;
    _position = _clamp(_position + delta);
    notifyListeners();
  }

  void endScrub() {
    if (!_scrubbing) return;
    _scrubbing = false;
    if (current.source != null) {
      _audio.seek(_position);
      if (_resumeAfterScrub) _audio.play();
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ disc spin
  /// Current disc rotation in radians. Shared so every disc on screen stays in sync.
  final ValueNotifier<double> discAngle = ValueNotifier(0);
  double _discSpeed = 0; // rad/s
  Duration? _lastFrame;

  /// Called every frame by each [VinylDisc]; runs once per frame no matter
  /// how many discs are visible.
  void tickDisc() {
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    if (_lastFrame == now) return;
    final double dt = _lastFrame == null
        ? 0.0
        : ((now - _lastFrame!).inMicroseconds / 1e6).clamp(0.0, 0.1).toDouble();
    _lastFrame = now;
    if (_scrubbing) return;
    final target = _playing ? spinDegreesPerSecond * math.pi / 180 : 0.0;
    _discSpeed += (target - _discSpeed) * math.min(1.0, dt * 3); // spin up / down
    if (_discSpeed.abs() > 1e-3) discAngle.value += _discSpeed * dt;
  }

  void rotateDiscBy(double radians) => discAngle.value += radians;

  // ---------------------------------------------------------- scratch sound
  final ScratchSound _scratch = ScratchSound();
  int _scratchDir = 0; // 1 = forward (clockwise), -1 = backward
  double _scratchTravel = 0; // radians moved since the last sound
  double _scratchSpeed = 0; // smoothed rad/s
  bool _scratchFiredThisStroke = false;
  DateTime? _lastScratchMove;
  DateTime _lastScratchSound = DateTime.fromMillisecondsSinceEpoch(0);

  /// Called while the disc is dragged. Plays a scratch each time the hand
  /// changes direction, and again every ~60 degrees of a long stroke.
  void scratch(double radians) {
    if (radians == 0) return;
    final now = DateTime.now();
    final last = _lastScratchMove;
    final dt = last == null ? 1 / 60 : now.difference(last).inMicroseconds / 1e6;
    _lastScratchMove = now;
    final speed = radians.abs() / dt.clamp(1 / 120, 0.1);
    _scratchSpeed = _scratchSpeed == 0 ? speed : _scratchSpeed * .6 + speed * .4;

    final dir = radians > 0 ? 1 : -1;
    if (dir != _scratchDir) {
      _scratchDir = dir;
      _scratchTravel = 0;
      _scratchFiredThisStroke = false;
    }
    _scratchTravel += radians.abs();

    if (now.difference(_lastScratchSound) < const Duration(milliseconds: 60)) return;
    final startOfStroke = !_scratchFiredThisStroke && _scratchTravel > .04;
    if (startOfStroke || _scratchTravel > 1.0) {
      _scratchFiredThisStroke = true;
      _scratchTravel = 0;
      _lastScratchSound = now;
      if (settings.scratchSounds) _scratch.play(forward: dir > 0, speed: _scratchSpeed);
      if (settings.haptics) HapticFeedback.selectionClick();
    }
  }

  /// True while the disc is playing or still slowing down.
  bool get discMoving => _playing || _discSpeed.abs() > 1e-3;

  /// Forget the last frame time so the next spin-up starts cleanly.
  void resetDiscClock() {
    _lastFrame = null;
    if (!_playing) _discSpeed = 0;
  }

  // -------------------------------------------------------------- private
  Future<void> _restore() async {
    try {
      _musicDirPath = (await _store.musicDir()).path;
    } catch (_) {}
    final data = await _store.load();
    if (data == null) {
      _applySavedEffects();
      return;
    }
    final saved = data['settings'];
    if (saved is Map) settings.load(Map<String, dynamic>.from(saved));
    final st = data['stats'];
    if (st is Map) stats.load(Map<String, dynamic>.from(st));
    for (final h in (data['hidden'] as List? ?? const [])) {
      if (h is String) _hidden.add(h);
    }
    _applySavedEffects();

    final songs = <Track>[];
    for (final j in (data['songs'] as List? ?? const [])) {
      try {
        final t = Track.fromJson(Map<String, dynamic>.from(j as Map));
        final src = t.source;
        if (src != null && File(src).existsSync()) songs.add(t); // skip missing files
      } catch (e) {
        debugPrint('Nightfall: skipped a saved song → $e');
      }
    }
    final ids = {for (final t in songs) t.id};

    final lists = <Playlist>[];
    for (final j in (data['playlists'] as List? ?? const [])) {
      try {
        final p = Playlist.fromJson(Map<String, dynamic>.from(j as Map));
        p.songIds.removeWhere((id) => !ids.contains(id));
        lists.add(p);
      } catch (e) {
        debugPrint('Nightfall: skipped a saved playlist → $e');
      }
    }

    // Anything imported while we were loading goes after the saved songs.
    final importedMeanwhile = List.of(_library);
    _library
      ..clear()
      ..addAll(songs)
      ..addAll(importedMeanwhile);
    _playlists
      ..clear()
      ..addAll(lists);
    for (final id in (data['liked'] as List? ?? const [])) {
      if (id is String && ids.contains(id)) _liked.add(id);
    }

    if (_tracks.isEmpty && _library.isNotEmpty) {
      _tracks = List.of(_library);
      _queuePlaylistId = null;
      select(0, autoplay: false);
    } else {
      notifyListeners();
    }
  }

  void _save() => _store.save({
        'version': 1,
        'songs': [for (final t in _library) t.toJson()],
        'playlists': [for (final p in _playlists) p.toJson()],
        'liked': _liked.toList(),
        'hidden': _hidden.toList(),
        'settings': settings.toJson(),
        'stats': stats.toJson(),
      });

  /// Takes a song out of the play queue, keeping the right song playing.
  void _removeFromQueue(String id) {
    final i = _tracks.indexWhere((x) => x.id == id);
    if (i < 0) return;
    final wasCurrent = i == _index;
    _tracks.removeAt(i);
    if (_tracks.isEmpty) {
      _index = 0;
      _load(play: false);
    } else if (i < _index) {
      _index--;
    } else if (wasCurrent) {
      if (_index >= _tracks.length) _index = 0;
      _load(play: _playing);
    }
  }

  Duration _clamp(Duration p) {
    if (p < Duration.zero) return Duration.zero;
    final d = duration;
    return (d > Duration.zero && p > d) ? d : p;
  }

  Future<void> _load({required bool play}) async {
    final id = ++_loadId;
    _heardThisPlay = Duration.zero;
    _countedThisPlay = false;
    _position = Duration.zero;
    _realDuration = null;
    _playing = play && _tracks.isNotEmpty;
    notifyListeners();

    final src = _tracks.isEmpty ? null : current.source;
    if (src == null) {
      _playing = false;
      await _audio.stop();
      return;
    }
    try {
      if (src.startsWith('http')) {
        await _audio.setUrl(src);
      } else if (src.startsWith('assets/')) {
        await _audio.setAsset(src);
      } else {
        await _audio.setFilePath(src);
      }
      if (id == _loadId && _playing) _audio.play();
    } catch (e) {
      debugPrint('Nightfall: could not load $src → $e');
      if (id == _loadId) {
        _playing = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _audio.dispose();
    _scratch.dispose();
    discAngle.dispose();
    super.dispose();
  }
}
