import 'dart:math' as math;

enum RepeatSetting { off, all, one }

/// Everything the Settings screen controls. Saved with the library.
class AppSettings {
  bool scratchSounds = true;
  bool haptics = true;
  bool autoScan = true;
  bool shuffle = false;
  RepeatSetting repeat = RepeatSetting.all;
  bool eqEnabled = false;
  String eqPreset = 'Flat';
  List<double> eqGains = [];
  double boostDb = 0;

  Map<String, Object?> toJson() => {
        'scratchSounds': scratchSounds,
        'haptics': haptics,
        'autoScan': autoScan,
        'shuffle': shuffle,
        'repeat': repeat.name,
        'eqEnabled': eqEnabled,
        'eqPreset': eqPreset,
        'eqGains': eqGains,
        'boostDb': boostDb,
      };

  void load(Map<String, dynamic> j) {
    scratchSounds = j['scratchSounds'] as bool? ?? scratchSounds;
    haptics = j['haptics'] as bool? ?? haptics;
    autoScan = j['autoScan'] as bool? ?? autoScan;
    shuffle = j['shuffle'] as bool? ?? shuffle;
    repeat = RepeatSetting.values.firstWhere((m) => m.name == j['repeat'], orElse: () => repeat);
    eqEnabled = j['eqEnabled'] as bool? ?? eqEnabled;
    eqPreset = j['eqPreset'] as String? ?? eqPreset;
    eqGains = [
      for (final g in (j['eqGains'] as List? ?? const []))
        if (g is num) g.toDouble(),
    ];
    boostDb = (j['boostDb'] as num?)?.toDouble() ?? boostDb;
  }
}

// ------------------------------------------------------------- EQ presets

const List<String> eqPresets = ['Flat', 'Bass boost', 'Vocal', 'Treble boost', 'Rock', 'Pop', 'Electronic'];

/// Preset shapes in dB at 60 Hz, 230 Hz, 910 Hz, 3.6 kHz and 14 kHz.
const Map<String, List<double>> _presetShapes = {
  'Flat': [0, 0, 0, 0, 0],
  'Bass boost': [6, 4, 0, 0, 0],
  'Vocal': [-2, -1, 3, 3, 0],
  'Treble boost': [0, 0, 0, 3, 6],
  'Rock': [4, 2, -1, 2, 4],
  'Pop': [-1, 2, 4, 2, -1],
  'Electronic': [5, 3, 0, 2, 4],
};
const List<double> _anchors = [60, 230, 910, 3600, 14000];

/// Gain (dB) that [preset] gives a band centred on [hz]. Works for any
/// number of bands, because phones differ.
double eqPresetGain(String preset, double hz) {
  final g = _presetShapes[preset];
  if (g == null) return 0;
  final x = math.log(hz.clamp(_anchors.first, _anchors.last));
  for (var i = 0; i < _anchors.length - 1; i++) {
    final a = math.log(_anchors[i]);
    final b = math.log(_anchors[i + 1]);
    if (x <= b) return g[i] + (g[i + 1] - g[i]) * ((x - a) / (b - a));
  }
  return g.last;
}

// ----------------------------------------------------------------- stats

class SongStats {
  int plays = 0;
  int ms = 0; // time listened
  int? last; // last played, ms since epoch

  Map<String, Object?> toJson() => {'plays': plays, 'ms': ms, 'last': last};

  static SongStats fromJson(Map<String, dynamic> j) => SongStats()
    ..plays = (j['plays'] as num?)?.toInt() ?? 0
    ..ms = (j['ms'] as num?)?.toInt() ?? 0
    ..last = (j['last'] as num?)?.toInt();
}

/// Listening history: time listened, play counts, recently played.
/// A play counts after 30 seconds (or half of a song shorter than a minute).
class ListeningStats {
  int totalMs = 0;
  final Map<String, SongStats> songs = {};
  final List<String> recent = []; // song ids, newest first

  SongStats song(String id) => songs.putIfAbsent(id, SongStats.new);

  int get totalPlays => songs.values.fold(0, (sum, s) => sum + s.plays);
  int get songsPlayed => songs.values.where((s) => s.plays > 0).length;

  void markRecent(String id) {
    recent.remove(id);
    recent.insert(0, id);
    if (recent.length > 50) recent.removeRange(50, recent.length);
  }

  void forget(String id) {
    songs.remove(id);
    recent.remove(id);
  }

  void clear() {
    totalMs = 0;
    songs.clear();
    recent.clear();
  }

  Map<String, Object?> toJson() => {
        'totalMs': totalMs,
        'songs': {for (final e in songs.entries) e.key: e.value.toJson()},
        'recent': recent,
      };

  void load(Map<String, dynamic> j) {
    clear();
    totalMs = (j['totalMs'] as num?)?.toInt() ?? 0;
    final s = j['songs'];
    if (s is Map) {
      for (final e in s.entries) {
        if (e.key is String && e.value is Map) {
          songs[e.key as String] = SongStats.fromJson(Map<String, dynamic>.from(e.value as Map));
        }
      }
    }
    for (final id in (j['recent'] as List? ?? const [])) {
      if (id is String) recent.add(id);
    }
  }
}
