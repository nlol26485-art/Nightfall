import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'player_controller.dart';
import 'theme.dart';
import 'vinyl_disc.dart';
import 'widgets.dart';

/// Library screen: like button, small spinning disc, import button, and two
/// tabs: every song, and your playlists.
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({
    super.key,
    required this.controller,
    this.title = 'LIBRARY',
    this.onImport,
    this.onBack,
  });

  final PlayerController controller;
  final String title;

  /// Called by the "+" button and the footer link (e.g. `importAudioFiles`).
  final VoidCallback? onImport;

  /// Optional back action (e.g. return to the Now Playing page).
  final VoidCallback? onBack;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  int _tab = 0; // 0 = Songs, 1 = Playlists
  String? _openId; // playlist being viewed in the Playlists tab

  PlayerController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: NP.screenGradient),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) {
              final open = _openId == null ? null : c.playlistById(_openId!);
              final String count;
              if (_tab == 0) {
                count = _plural(c.library.length, 'Song');
              } else if (open != null) {
                count = _plural(c.tracksOf(open).length, 'Song');
              } else {
                count = _plural(c.playlists.length, 'Playlist');
              }

              return Column(
                children: [
                  SizedBox(
                    height: 42,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(widget.title, style: NP.eyebrow),
                        if (widget.onBack != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: NeuButton(
                                icon: Icons.arrow_back_rounded, onTap: widget.onBack, size: 38, tooltip: 'Back'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        NeuButton(
                          icon: c.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: c.isLiked ? NP.accent : null,
                          glow: c.isLiked,
                          onTap: c.toggleLike,
                          tooltip: 'Favorite song',
                        ),
                        Container(
                          width: 120,
                          height: 120,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: NP.raisedGradient,
                            boxShadow: NP.raised(10),
                          ),
                          child: VinylDisc(controller: c, size: 100),
                        ),
                        NeuButton(icon: Icons.add_rounded, onTap: widget.onImport, tooltip: 'Import songs'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _Tabs(
                          selected: _tab,
                          onSelect: (i) => setState(() => _tab = i),
                        ),
                        Text(count,
                            style: const TextStyle(fontSize: 12, color: NP.muted, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: KeyedSubtree(
                        key: ValueKey('$_tab/${open?.id}'),
                        child: _tab == 0
                            ? _songsTab()
                            : (open != null ? _playlistDetail(open) : _playlistsTab()),
                      ),
                    ),
                  ),

                  _footer(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- tabs

  Widget _songsTab() {
    final songs = c.library;
    if (songs.isEmpty) {
      return _empty(Icons.library_music_rounded, 'No songs yet', 'Tap + to import music from your phone.');
    }
    return _fade(ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: songs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final t = songs[i];
        final active = c.isCurrent(t);
        return _TrackTile(
          track: t,
          active: active,
          playing: active && c.playing,
          onTap: () => active ? c.toggle() : c.playFrom(songs, i),
          onMore: () => _songMenu(t),
        );
      },
    ));
  }

  Widget _playlistsTab() {
    final lists = c.playlists;
    return _fade(ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: lists.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        if (i == 0) return _NewPlaylistTile(onTap: () => _createPlaylist());
        final p = lists[i - 1];
        final songs = c.tracksOf(p);
        final active = c.queuePlaylistId == p.id && !c.isEmpty;
        return _PlaylistTile(
          name: p.name,
          count: songs.length,
          active: active,
          playing: active && c.playing,
          onTap: () => setState(() => _openId = p.id),
          onPlay: songs.isEmpty ? null : () => active ? c.toggle() : c.playFrom(songs, 0, playlistId: p.id),
          onMore: () => _playlistMenu(p),
        );
      },
    ));
  }

  Widget _playlistDetail(Playlist p) {
    final songs = c.tracksOf(p);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              NeuButton(
                icon: Icons.chevron_left_rounded,
                size: 34,
                onTap: () => setState(() => _openId = null),
                tooltip: 'All playlists',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, color: NP.text, fontWeight: FontWeight.w600),
                ),
              ),
              NeuButton(icon: Icons.playlist_add_rounded, size: 34, onTap: () => _pickSongs(p), tooltip: 'Add songs'),
              const SizedBox(width: 10),
              NeuButton(
                  icon: Icons.more_horiz_rounded, size: 34, onTap: () => _playlistMenu(p), tooltip: 'Playlist options'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: songs.isEmpty
              ? _empty(Icons.queue_music_rounded, 'This playlist is empty', 'Tap the add button above to pick songs.')
              : _fade(ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: songs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final t = songs[i];
                    final active = c.isCurrent(t);
                    return _TrackTile(
                      track: t,
                      active: active,
                      playing: active && c.playing,
                      onTap: () => active && c.queuePlaylistId == p.id
                          ? c.toggle()
                          : c.playFrom(songs, i, playlistId: p.id),
                      onMore: () => _songMenu(t, inPlaylist: p),
                    );
                  },
                )),
        ),
      ],
    );
  }

  Widget _footer() {
    final status = c.importStatus;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: NP.light.withValues(alpha: .6))),
      ),
      child: Column(
        children: [
          if (status != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.6, color: NP.accent),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: NP.accent, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            )
          else
            GestureDetector(
              onTap: widget.onImport,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 16, color: NP.accent),
                    SizedBox(width: 4),
                    Text('Import Audio Files from Device',
                        style: TextStyle(fontSize: 12, color: NP.accent, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 2),
          const Text('MP3 · AAC · OGG · Lossless & Hi-Res FLAC, WAV, ALAC',
              style: TextStyle(fontSize: 9.5, color: NP.faint)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ menus

  void _songMenu(Track t, {Playlist? inPlaylist}) {
    final pl = inPlaylist;
    _sheet(
      title: t.title,
      subtitle: t.qualityText,
      items: (ctx) => [
        _action(ctx, Icons.playlist_add_rounded, 'Add to playlist', () => _addToPlaylistSheet(t)),
        if (pl != null)
          _action(ctx, Icons.playlist_remove_rounded, 'Remove from "${pl.name}"', () {
            c.removeFromPlaylist(pl.id, t);
            _toast('Removed from ${pl.name}');
          }),
        _action(ctx, Icons.delete_outline_rounded, 'Delete from library', () async {
          final ok = await _confirm(
            'Delete "${t.title}"?',
            'It will be removed from the app and from all playlists. The original file on your phone is not touched.',
            'Delete',
          );
          if (ok) c.removeFromLibrary(t);
        }, danger: true),
      ],
    );
  }

  void _addToPlaylistSheet(Track t) {
    _sheet(
      title: 'Add to playlist',
      subtitle: t.title,
      items: (ctx) => [
        _action(ctx, Icons.add_rounded, 'New playlist…', () => _createPlaylist(withSong: t), accent: true),
        for (final p in c.playlists)
          if (p.songIds.contains(t.id))
            ListTile(
              enabled: false,
              leading: const Icon(Icons.check_rounded, color: NP.accent, size: 22),
              title: Text(p.name, style: const TextStyle(fontSize: 13.5, color: NP.muted)),
              subtitle: const Text('Already added', style: TextStyle(fontSize: 11, color: NP.faint)),
            )
          else
            _action(ctx, Icons.queue_music_rounded, p.name, () {
              c.addToPlaylist(p.id, [t]);
              _toast('Added to ${p.name}');
            }),
      ],
    );
  }

  void _playlistMenu(Playlist p) {
    final songs = c.tracksOf(p);
    _sheet(
      title: p.name,
      subtitle: _plural(songs.length, 'song'),
      items: (ctx) => [
        if (songs.isNotEmpty)
          _action(ctx, Icons.play_arrow_rounded, 'Play', () => c.playFrom(songs, 0, playlistId: p.id)),
        _action(ctx, Icons.playlist_add_rounded, 'Add songs', () => _pickSongs(p)),
        _action(ctx, Icons.edit_outlined, 'Rename', () async {
          final name = await _askName('Rename playlist', initial: p.name, action: 'Save');
          if (name != null) c.renamePlaylist(p.id, name);
        }),
        _action(ctx, Icons.delete_outline_rounded, 'Delete playlist', () async {
          final ok = await _confirm(
              'Delete "${p.name}"?', 'The playlist is removed. Its songs stay in your library.', 'Delete');
          if (!ok) return;
          c.deletePlaylist(p.id);
          if (mounted && _openId == p.id) setState(() => _openId = null);
        }, danger: true),
      ],
    );
  }

  Future<void> _createPlaylist({Track? withSong}) async {
    final name = await _askName('New playlist');
    if (name == null || !mounted) return;
    final p = c.createPlaylist(name);
    if (withSong != null) {
      c.addToPlaylist(p.id, [withSong]);
      _toast('Added to ${p.name}');
      return;
    }
    setState(() {
      _tab = 1;
      _openId = p.id;
    });
    if (c.library.isNotEmpty) await _pickSongs(p);
  }

  /// Checklist of library songs to add to [p].
  Future<void> _pickSongs(Playlist p) async {
    final songs = c.library;
    if (songs.isEmpty) {
      _toast('Import some songs first');
      return;
    }
    final chosen = <String>{};
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: NP.card,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .8),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Add to ${p.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, color: NP.text, fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: chosen.isEmpty ? null : () => Navigator.pop(ctx, true),
                      child: Text(
                        chosen.isEmpty ? 'Add' : 'Add ${chosen.length}',
                        style: TextStyle(
                          color: chosen.isEmpty ? NP.faint : NP.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: songs.length,
                  itemBuilder: (_, i) {
                    final t = songs[i];
                    final already = p.songIds.contains(t.id);
                    return CheckboxListTile(
                      value: already || chosen.contains(t.id),
                      onChanged: already
                          ? null
                          : (v) => setSheet(() {
                                if (v == true) {
                                  chosen.add(t.id);
                                } else {
                                  chosen.remove(t.id);
                                }
                              }),
                      activeColor: NP.accent,
                      checkColor: Colors.white,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: already ? NP.faint : NP.text),
                      ),
                      subtitle: Text(
                        already ? 'Already in playlist' : (t.qualityText ?? t.artist),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: NP.muted),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    final n = c.addToPlaylist(p.id, [
      for (final t in songs)
        if (chosen.contains(t.id)) t,
    ]);
    _toast('Added ${_plural(n, 'song')} to ${p.name}');
  }

  // ---------------------------------------------------------------- helpers

  Future<void> _sheet({
    required String title,
    String? subtitle,
    required List<Widget> Function(BuildContext ctx) items,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: NP.card,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .75),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, color: NP.text, fontWeight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: NP.muted)),
                    ],
                  ],
                ),
              ),
              Flexible(child: ListView(shrinkWrap: true, children: items(ctx))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(BuildContext ctx, IconData icon, String label, VoidCallback onTap,
      {bool danger = false, bool accent = false}) {
    final color = danger || accent ? NP.accent : NP.text;
    return ListTile(
      leading: Icon(icon, color: danger || accent ? NP.accent : NP.muted, size: 22),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: color)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
    );
  }

  Future<String?> _askName(String title, {String initial = '', String action = 'Create'}) {
    final text = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NP.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(title, style: const TextStyle(fontSize: 16, color: NP.text, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: text,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          cursorColor: NP.accent,
          style: const TextStyle(color: NP.text),
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: NP.faint),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: NP.faint)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: NP.accent)),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: NP.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, text.text),
            child: Text(action, style: const TextStyle(color: NP.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NP.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(title, style: const TextStyle(fontSize: 16, color: NP.text, fontWeight: FontWeight.w600)),
        content: Text(message, style: const TextStyle(fontSize: 13, color: NP.muted, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: NP.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action, style: const TextStyle(color: NP.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message, style: const TextStyle(color: NP.text)),
        backgroundColor: NP.card,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ));
  }

  Widget _empty(IconData icon, String title, String hint) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: NP.faint),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 13.5, color: NP.muted, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(hint, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: NP.faint)),
          ],
        ),
      ),
    );
  }

  /// Soft fade at the bottom of a list.
  Widget _fade(Widget list) {
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, .88, 1],
      ).createShader(r),
      blendMode: BlendMode.dstIn,
      child: list,
    );
  }

  static String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
}

// -------------------------------------------------------------------- widgets

class _Tabs extends StatelessWidget {
  const _Tabs({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    const labels = ['Songs', 'Playlists'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: NP.insetGradient,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => onSelect(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: i == selected ? NP.raisedGradient : null,
                  boxShadow: i == selected ? NP.raised(2) : null,
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: i == selected ? NP.accent : NP.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Icon(Icons.more_vert_rounded, size: 18, color: NP.muted),
      ),
    );
  }
}

class _PlayDot extends StatelessWidget {
  const _PlayDot({required this.active, required this.playing, this.enabled = true});

  final bool active;
  final bool playing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: active ? NP.playGradient : NP.raisedGradient,
        boxShadow: active ? NP.accentGlow(14, .55) : NP.raised(3),
      ),
      child: Icon(
        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        size: 15,
        color: active ? Colors.white : (enabled ? NP.muted : NP.faint),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.active,
    required this.playing,
    required this.onTap,
    required this.onMore,
  });

  final Track track;
  final bool active;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onMore,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: active ? NP.insetGradient : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (track.badge != null) ...[
                        QualityBadge(track: track),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          track.isLossless ? (track.qualityText ?? track.artist) : track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: NP.muted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              track.duration > Duration.zero ? NP.time(track.duration) : '--:--',
              style: const TextStyle(
                fontSize: 10.5,
                color: NP.muted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            _MoreButton(onTap: onMore),
            _PlayDot(active: active, playing: playing),
          ],
        ),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.name,
    required this.count,
    required this.active,
    required this.playing,
    required this.onTap,
    required this.onPlay,
    required this.onMore,
  });

  final String name;
  final int count;
  final bool active;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onMore,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: active ? NP.insetGradient : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: NP.raisedGradient,
                boxShadow: NP.raised(3),
              ),
              child: Icon(Icons.queue_music_rounded, size: 20, color: active ? NP.accent : NP.muted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count ${count == 1 ? 'song' : 'songs'}',
                    style: const TextStyle(fontSize: 10.5, color: NP.muted),
                  ),
                ],
              ),
            ),
            _MoreButton(onTap: onMore),
            GestureDetector(
              onTap: onPlay,
              behavior: HitTestBehavior.opaque,
              child: _PlayDot(active: active, playing: playing, enabled: onPlay != null),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewPlaylistTile extends StatelessWidget {
  const _NewPlaylistTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: NP.insetGradient,
                border: Border.all(color: NP.accent.withValues(alpha: .5)),
              ),
              child: const Icon(Icons.add_rounded, size: 22, color: NP.accent),
            ),
            const SizedBox(width: 12),
            const Text('New playlist',
                style: TextStyle(fontSize: 12.5, color: NP.accent, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
