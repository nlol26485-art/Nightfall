import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import 'equalizer_screen.dart';
import 'music_scanner.dart';
import 'player_controller.dart';
import 'settings.dart';
import 'stats_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Settings: sound effects, playback (equalizer, sleep timer, shuffle,
/// repeat), library (auto-add from the phone) and listening stats.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return NFPage(
      title: 'SETTINGS',
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final s = c.settings;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              NFSection(title: 'SOUND EFFECTS', children: [
                NFSwitchRow(
                  icon: Icons.album_rounded,
                  title: 'Scratch sound',
                  subtitle: 'Vinyl scratch when you drag the disc',
                  value: s.scratchSounds,
                  onChanged: (v) => c.updateSettings((s) => s.scratchSounds = v),
                ),
                NFSwitchRow(
                  icon: Icons.vibration_rounded,
                  title: 'Vibration',
                  subtitle: 'A light tick with each scratch',
                  value: s.haptics,
                  onChanged: (v) => c.updateSettings((s) => s.haptics = v),
                ),
              ]),
              NFSection(title: 'PLAYBACK', children: [
                NFRow(
                  icon: Icons.equalizer_rounded,
                  title: 'Equalizer',
                  subtitle: s.eqEnabled ? s.eqPreset : 'Off',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => EqualizerScreen(controller: c)),
                  ),
                ),
                NFRow(
                  icon: Icons.bedtime_outlined,
                  title: 'Sleep timer',
                  subtitle: _sleepText(context, c),
                  onTap: () => _sleepSheet(context, c),
                ),
                NFSwitchRow(
                  icon: Icons.shuffle_rounded,
                  title: 'Shuffle',
                  value: s.shuffle,
                  onChanged: (_) => c.toggleShuffle(),
                ),
                NFRow(
                  icon: s.repeat == RepeatSetting.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                  title: 'Repeat',
                  trailing: _Segments(
                    labels: const ['Off', 'All', 'One'],
                    selected: s.repeat.index,
                    onSelect: (i) => c.updateSettings((s) => s.repeat = RepeatSetting.values[i]),
                  ),
                ),
              ]),
              NFSection(title: 'LIBRARY', children: [
                NFSwitchRow(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Add new songs automatically',
                  subtitle: 'Checks your phone each time the app opens',
                  value: s.autoScan,
                  onChanged: (v) {
                    c.updateSettings((s) => s.autoScan = v);
                    if (v) _scan(context, c);
                  },
                ),
                NFRow(
                  icon: Icons.manage_search_rounded,
                  title: 'Scan phone for music now',
                  subtitle: c.scanStatus ?? _lastScanText(c),
                  trailing: c.scanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 1.8, color: NP.accent),
                        )
                      : null,
                  onTap: c.scanning ? null : () => _scan(context, c),
                ),
                if (c.hiddenCount > 0)
                  NFRow(
                    icon: Icons.visibility_outlined,
                    title: 'Show removed songs again',
                    subtitle: '${c.hiddenCount} phone ${c.hiddenCount == 1 ? 'song' : 'songs'} you removed',
                    onTap: () {
                      c.unhideAll();
                      _scan(context, c);
                    },
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    'Searched folders: ${scanFolders.join(', ')}. Songs found there are played in place, '
                    'so they take no extra space. Songs added with + are copied into the app.',
                    style: const TextStyle(fontSize: 10.5, color: NP.faint, height: 1.4),
                  ),
                ),
              ]),
              NFSection(title: 'STATS', children: [
                NFRow(
                  icon: Icons.insights_rounded,
                  title: 'Listening stats',
                  subtitle: 'Most played, recently played, library size',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => StatsScreen(controller: c)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              const Center(
                child: Text('Nightfall 1.0', style: TextStyle(fontSize: 10.5, color: NP.faint)),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _sleepText(BuildContext context, PlayerController c) {
    if (c.sleepAtEndOfSong) return 'At the end of this song';
    final at = c.sleepAt;
    if (at == null) return 'Off';
    return 'Pauses at ${TimeOfDay.fromDateTime(at).format(context)}';
  }

  static String _lastScanText(PlayerController c) {
    final at = c.lastScan;
    if (at == null) return 'Finds songs in Music, Download and more';
    final n = c.lastScanAdded ?? 0;
    return n == 0 ? 'Up to date' : 'Added $n new ${n == 1 ? 'song' : 'songs'}';
  }

  static Future<void> _scan(BuildContext context, PlayerController c) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await scanPhoneForMusic(c);
    switch (result) {
      case ScanResult.noPermission:
        messenger.showSnackBar(SnackBar(
          content: const Text('Nightfall needs access to music to find your songs.'),
          action: SnackBarAction(label: 'Open settings', textColor: NP.accent, onPressed: openAppSettings),
        ));
      case ScanResult.unsupported:
        messenger.showSnackBar(const SnackBar(content: Text('Scanning works on Android phones.')));
      case ScanResult.done:
        final n = c.lastScanAdded ?? 0;
        messenger.showSnackBar(SnackBar(
          content: Text(n == 0 ? 'No new songs found' : 'Added $n new ${n == 1 ? 'song' : 'songs'}'),
        ));
      case ScanResult.busy:
        break;
    }
  }

  static void _sleepSheet(BuildContext context, PlayerController c) {
    void pick(BuildContext ctx, {Duration? after, bool endOfSong = false}) {
      Navigator.pop(ctx);
      c.setSleepTimer(after: after, endOfSong: endOfSong);
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NP.card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Sleep timer',
                    style: TextStyle(fontSize: 15, color: NP.text, fontWeight: FontWeight.w600)),
              ),
              for (final m in const [15, 30, 45, 60])
                _sheetOption(Icons.timer_outlined, '$m minutes', () => pick(ctx, after: Duration(minutes: m))),
              _sheetOption(Icons.music_note_rounded, 'End of this song', () => pick(ctx, endOfSong: true)),
              _sheetOption(Icons.timer_off_outlined, 'Off', () => pick(ctx)),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _sheetOption(IconData icon, String label, VoidCallback onTap) => ListTile(
        leading: Icon(icon, color: NP.muted, size: 22),
        title: Text(label, style: const TextStyle(fontSize: 13.5, color: NP.text)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap,
      );
}

// ------------------------------------------------------------------------
// Building blocks shared by the Settings, Equalizer and Stats pages.

/// Full-screen page with a back button and a small title.
class NFPage extends StatelessWidget {
  const NFPage({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NP.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: NP.screenGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: SizedBox(
                  height: 42,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(title, style: NP.eyebrow),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: NeuButton(
                          icon: Icons.arrow_back_rounded,
                          size: 38,
                          onTap: () => Navigator.of(context).maybePop(),
                          tooltip: 'Back',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled, raised card holding rows.
class NFSection extends StatelessWidget {
  const NFSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 10),
            child: Text(title, style: NP.eyebrow),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: NP.raisedGradient,
              boxShadow: NP.raised(6),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

/// Icon, title, optional subtitle, optional trailing widget (a chevron if tappable).
class NFRow extends StatelessWidget {
  const NFRow({super.key, required this.icon, required this.title, this.subtitle, this.trailing, this.onTap});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: NP.muted),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13.5, color: NP.text, fontWeight: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: const TextStyle(fontSize: 11, color: NP.muted)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                (onTap != null
                    ? const Icon(Icons.chevron_right_rounded, size: 20, color: NP.faint)
                    : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

class NFSwitchRow extends StatelessWidget {
  const NFSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return NFRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => onChanged(!value),
      trailing: NFSwitch(value: value, onChanged: onChanged),
    );
  }
}

class NFSwitch extends StatelessWidget {
  const NFSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: NP.accent,
      inactiveTrackColor: NP.dark,
      inactiveThumbColor: NP.muted,
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.labels, required this.selected, required this.onSelect});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: NP.insetGradient),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => onSelect(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: i == selected ? NP.raisedGradient : null,
                  boxShadow: i == selected ? NP.raised(2) : null,
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 11,
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
