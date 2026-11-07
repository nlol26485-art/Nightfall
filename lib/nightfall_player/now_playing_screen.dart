import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'player_controller.dart';
import 'settings.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'vinyl_disc.dart';
import 'widgets.dart';

/// "Playing now" screen: big interactive disc, title, seek bar, controls.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({
    super.key,
    required this.controller,
    this.onBack,
    this.onOpenPlaylist,
    this.discCaption = 'NIGHTFALL',
  });

  final PlayerController controller;
  final VoidCallback? onBack;
  final VoidCallback? onOpenPlaylist;
  final String discCaption;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // Shrink the disc on short phones so everything still fits.
    final well = math.min(math.min(screen.width * .66, 280.0), screen.height * .32);
    const pad = 14.0;

    return DecoratedBox(
      decoration: const BoxDecoration(gradient: NP.screenGradient),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final c = controller;
              final t = c.current;
              return Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      NeuButton(
                        icon: Icons.tune_rounded,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => SettingsScreen(controller: c)),
                        ),
                        tooltip: 'Settings',
                      ),
                      const Text('PLAYING NOW', style: NP.eyebrow),
                      NeuButton(icon: Icons.menu_rounded, onTap: onOpenPlaylist, tooltip: 'Playlist'),
                    ],
                  ),
                  const Spacer(),

                  // Disc in its raised well, with the tonearm on top.
                  SizedBox.square(
                    dimension: well,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 800),
                          width: well,
                          height: well,
                          padding: const EdgeInsets.all(pad),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: NP.raisedGradient,
                            boxShadow: [
                              ...NP.raised(16),
                              BoxShadow(
                                color: NP.accent.withValues(alpha: c.playing ? .14 : 0),
                                blurRadius: 60,
                              ),
                            ],
                          ),
                          child: VinylDisc(controller: c, size: well - pad * 2, caption: discCaption),
                        ),
                        Positioned(
                          right: -16,
                          top: -8,
                          child: Transform.scale(
                            scale: well / 240, // arm was drawn for a 240px disc
                            alignment: const Alignment(0, -1 + 20 / 150),
                            child: Tonearm(down: c.playing),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tap disc to play/pause · Drag to scratch',
                    style: TextStyle(fontSize: 10, color: NP.faint, letterSpacing: .3),
                  ),
                  const Spacer(),

                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: NP.text),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: NP.muted),
                  ),
                  if (t.isLossless && t.qualityText != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        QualityBadge(track: t, large: true),
                        const SizedBox(width: 8),
                        Text(t.qualityText!, style: const TextStyle(fontSize: 10.5, color: NP.muted)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 26),

                  SeekBar(progress: c.progress, onSeek: c.seekFraction),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(NP.time(c.position), style: const TextStyle(fontSize: 10, color: NP.muted)),
                      Text(NP.time(c.duration), style: const TextStyle(fontSize: 10, color: NP.muted)),
                    ],
                  ),
                  const Spacer(),

                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: NeuButton(
                            icon: Icons.shuffle_rounded,
                            size: 38,
                            color: c.settings.shuffle ? NP.accent : null,
                            glow: c.settings.shuffle,
                            onTap: c.toggleShuffle,
                            tooltip: c.settings.shuffle ? 'Shuffle on' : 'Shuffle off',
                          ),
                        ),
                      ),
                      NeuButton(icon: Icons.skip_previous_rounded, size: 58, onTap: c.previous, tooltip: 'Previous'),
                      const SizedBox(width: 18),
                      PlayButton(playing: c.playing, onTap: c.toggle),
                      const SizedBox(width: 18),
                      NeuButton(icon: Icons.skip_next_rounded, size: 58, onTap: () => c.next(), tooltip: 'Next'),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: NeuButton(
                            icon: c.settings.repeat == RepeatSetting.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                            size: 38,
                            color: c.settings.repeat == RepeatSetting.off ? null : NP.accent,
                            glow: c.settings.repeat != RepeatSetting.off,
                            onTap: c.cycleRepeat,
                            tooltip: switch (c.settings.repeat) {
                              RepeatSetting.off => 'Repeat off',
                              RepeatSetting.all => 'Repeat all',
                              RepeatSetting.one => 'Repeat one',
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Volume
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Semantics(
                          button: true,
                          label: c.muted ? 'Unmute' : 'Mute',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: c.toggleMute,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                c.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                size: 18,
                                color: NP.muted,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: SeekBar(progress: c.volume, onSeek: c.setVolume)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
