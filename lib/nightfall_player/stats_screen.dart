import 'dart:io';

import 'package:flutter/material.dart';

import 'player_controller.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Listening stats and a summary of the library.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late final Future<int> _storage = _storageUsed(widget.controller.library);

  PlayerController get c => widget.controller;

  static Future<int> _storageUsed(List<Track> songs) async {
    var total = 0;
    for (final t in songs) {
      final src = t.source;
      if (src == null || src.startsWith('http') || src.startsWith('assets/')) continue;
      try {
        total += await File(src).length();
      } catch (_) {}
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return NFPage(
      title: 'LISTENING STATS',
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final st = c.stats;
          final lib = c.library;
          final byId = {for (final t in lib) t.id: t};

          final top = [
            for (final e in st.songs.entries)
              if (e.value.plays > 0 && byId.containsKey(e.key)) e,
          ]..sort((a, b) {
              final p = b.value.plays.compareTo(a.value.plays);
              return p != 0 ? p : b.value.ms.compareTo(a.value.ms);
            });
          final topSongs = [for (final e in top.take(10)) byId[e.key]!];

          final recent = [
            for (final id in st.recent)
              if (byId.containsKey(id)) byId[id]!,
          ].take(15).toList();

          final hiRes = lib.where((t) => t.isHiRes).length;
          final lossless = lib.where((t) => t.isLossless && !t.isHiRes).length;
          final totalLength = lib.fold<int>(0, (sum, t) => sum + t.duration.inMilliseconds);
          final unknownLengths = lib.where((t) => t.duration == Duration.zero).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _Tile(value: _time(st.totalMs), label: 'Listening time')),
                  const SizedBox(width: 14),
                  Expanded(child: _Tile(value: '${st.totalPlays}', label: 'Plays')),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _Tile(value: '${st.songsPlayed}', label: 'Different songs played')),
                  const SizedBox(width: 14),
                  Expanded(child: _Tile(value: '${lib.length}', label: 'Songs in library')),
                ],
              ),

              NFSection(title: 'MOST PLAYED', children: [
                if (topSongs.isEmpty)
                  _hint('Songs show up here after you listen for 30 seconds.')
                else
                  for (var i = 0; i < topSongs.length; i++)
                    _SongRow(
                      rank: '${i + 1}',
                      track: topSongs[i],
                      detail: '${_plays(st.song(topSongs[i].id).plays)} · ${_time(st.song(topSongs[i].id).ms)}',
                      onTap: () => c.playFrom(topSongs, i),
                    ),
              ]),

              NFSection(title: 'RECENTLY PLAYED', children: [
                if (recent.isEmpty)
                  _hint('Nothing yet.')
                else
                  for (var i = 0; i < recent.length; i++)
                    _SongRow(
                      track: recent[i],
                      detail: _ago(st.song(recent[i].id).last),
                      onTap: () => c.playFrom(recent, i),
                    ),
              ]),

              NFSection(title: 'LIBRARY', children: [
                _InfoRow('Songs', '${lib.length}'),
                _InfoRow('Playlists', '${c.playlists.length}'),
                _InfoRow('Hi-Res (24-bit or above 48 kHz)', '$hiRes'),
                _InfoRow('Lossless (CD quality)', '$lossless'),
                _InfoRow('Total length',
                    unknownLengths > 0 ? '${_time(totalLength)}+' : _time(totalLength)),
                FutureBuilder<int>(
                  future: _storage,
                  builder: (context, snap) =>
                      _InfoRow('Storage used', snap.hasData ? _bytes(snap.data!) : '…'),
                ),
              ]),

              const SizedBox(height: 22),
              Center(
                child: TextButton.icon(
                  onPressed: st.totalMs == 0 ? null : _confirmReset,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Reset listening stats'),
                  style: TextButton.styleFrom(foregroundColor: NP.accent, disabledForegroundColor: NP.faint),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NP.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Reset listening stats?',
            style: TextStyle(fontSize: 16, color: NP.text, fontWeight: FontWeight.w600)),
        content: const Text('Play counts, listening time and history are cleared. Your songs and playlists stay.',
            style: TextStyle(fontSize: 13, color: NP.muted, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: NP.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset', style: TextStyle(color: NP.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok == true) c.resetStats();
  }

  static Widget _hint(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(text, style: const TextStyle(fontSize: 11.5, color: NP.faint)),
      );

  static String _plays(int n) => '$n ${n == 1 ? 'play' : 'plays'}';

  static String _time(int ms) {
    final m = ms ~/ 60000;
    if (m == 0) return ms > 0 ? '${ms ~/ 1000}s' : '0m';
    final h = m ~/ 60;
    return h > 0 ? '${h}h ${m % 60}m' : '${m}m';
  }

  static String _ago(int? epochMs) {
    if (epochMs == null) return '';
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(epochMs));
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays == 1) return 'Yesterday';
    return '${d.inDays} days ago';
  }

  static String _bytes(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: NP.raisedGradient,
        boxShadow: NP.raised(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 22, color: NP.accent2, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: NP.muted)),
        ],
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({this.rank, required this.track, required this.detail, required this.onTap});

  final String? rank;
  final Track track;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (rank != null)
              SizedBox(
                width: 26,
                child: Text(rank!, style: const TextStyle(fontSize: 13, color: NP.accent, fontWeight: FontWeight.w600)),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: NP.text, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(detail, maxLines: 1, style: const TextStyle(fontSize: 10.5, color: NP.muted)),
                ],
              ),
            ),
            if (track.badge != null) ...[
              const SizedBox(width: 8),
              QualityBadge(track: track),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, color: NP.text))),
          Text(value, style: const TextStyle(fontSize: 12.5, color: NP.muted, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
