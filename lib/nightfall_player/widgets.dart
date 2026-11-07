import 'package:flutter/material.dart';

import 'player_controller.dart';
import 'theme.dart';

/// Round neumorphic button that sinks in when pressed.
class NeuButton extends StatefulWidget {
  const NeuButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 42,
    this.iconSize,
    this.color,
    this.glow = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double? iconSize;
  final Color? color;
  final bool glow;
  final String? tooltip;

  @override
  State<NeuButton> createState() => _NeuButtonState();
}

class _NeuButtonState extends State<NeuButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? NP.muted;
    final button = GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? .96 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: _down ? NP.insetGradient : NP.raisedGradient,
            boxShadow: _down ? NP.raised(1) : NP.raised(widget.size * .14),
          ),
          child: Icon(
            widget.icon,
            size: widget.iconSize ?? widget.size * .45,
            color: color,
            shadows: widget.glow ? [Shadow(color: color.withValues(alpha: .7), blurRadius: 10)] : null,
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: widget.tooltip == null ? button : Tooltip(message: widget.tooltip!, child: button),
    );
  }
}

/// Big orange play/pause button sitting in a sunken ring.
class PlayButton extends StatelessWidget {
  const PlayButton({super.key, required this.playing, required this.onTap, this.size = 70});

  final bool playing;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ring = size * 1.31;
    return Container(
      width: ring,
      height: ring,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: NP.insetGradient,
        border: Border.all(color: NP.light.withValues(alpha: .6), width: .8),
      ),
      alignment: Alignment.center,
      child: Semantics(
        button: true,
        label: playing ? 'Pause' : 'Play',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: NP.playGradient,
              boxShadow: [
                BoxShadow(color: NP.accent.withValues(alpha: .45), blurRadius: 28, offset: const Offset(0, 10)),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(playing),
                color: Colors.white,
                size: size * .44,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin glowing progress bar. Tap or drag to seek.
class SeekBar extends StatelessWidget {
  const SeekBar({super.key, required this.progress, required this.onSeek});

  final double progress; // 0–1
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final x = w * progress.clamp(0.0, 1.0);
      void seekAt(double dx) => onSeek((dx / w).clamp(0.0, 1.0).toDouble());

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => seekAt(d.localPosition.dx),
        onHorizontalDragStart: (d) => seekAt(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
        child: SizedBox(
          height: 24,
          child: Stack(
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0B0D),
                  borderRadius: BorderRadius.circular(4),
                  border: const Border(bottom: BorderSide(color: Color(0xFF222327), width: .8)),
                ),
              ),
              Container(
                width: x,
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(colors: [Color(0xFFA8360F), NP.accent, NP.accent2]),
                  boxShadow: NP.accentGlow(10, .55),
                ),
              ),
              Positioned(
                left: x - 7,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      center: Alignment(-0.3, -0.3),
                      colors: [Color(0xFFFFE0C8), NP.accent2],
                    ),
                    boxShadow: [
                      const BoxShadow(color: Color(0xFF141518), spreadRadius: 3),
                      BoxShadow(color: NP.accent2.withValues(alpha: .8), blurRadius: 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// Tonearm that swings onto the record while playing.
class Tonearm extends StatelessWidget {
  const Tonearm({super.key, required this.down});

  final bool down;

  @override
  Widget build(BuildContext context) {
    const shadow = [BoxShadow(color: Color(0x99000000), offset: Offset(2, 3), blurRadius: 6)];
    return IgnorePointer(
      child: AnimatedRotation(
        turns: down ? 21 / 360 : -6 / 360,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
        alignment: const Alignment(0, -1 + 20 / 150), // pivot = centre of the base
        child: SizedBox(
          width: 20,
          height: 150,
          child: Stack(
            children: [
              Positioned(
                top: 10,
                left: 8,
                child: Container(
                  width: 4,
                  height: 122,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: const LinearGradient(colors: [Color(0xFF6A6C73), Color(0xFF3A3B40)]),
                    boxShadow: shadow,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 3,
                child: Container(
                  width: 14,
                  height: 22,
                  alignment: Alignment.bottomCenter,
                  padding: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF4A4C52), Color(0xFF2A2B30)],
                    ),
                    boxShadow: shadow,
                  ),
                  child: Container(width: 4, height: 4, color: NP.accent),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [Color(0xFF303237), Color(0xFF1A1B1E)]),
                    boxShadow: NP.raised(3),
                  ),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: NP.accent, shape: BoxShape.circle),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small "HI-RES" / "LOSSLESS" tag. Shows nothing for lossy files.
class QualityBadge extends StatelessWidget {
  const QualityBadge({super.key, required this.track, this.large = false});

  final Track track;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final label = track.badge;
    if (label == null) return const SizedBox.shrink();
    final hi = track.isHiRes;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 7 : 5, vertical: large ? 2.5 : 1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: hi ? NP.accent : NP.faint, width: .8),
        color: hi ? NP.accent.withValues(alpha: .12) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: large ? 9.5 : 7.5,
          height: 1.2,
          letterSpacing: .8,
          fontWeight: FontWeight.w600,
          color: hi ? NP.accent2 : NP.muted,
        ),
      ),
    );
  }
}
