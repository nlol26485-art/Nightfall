import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'player_controller.dart';
import 'theme.dart';

/// Interactive vinyl record.
///  * Spins while playing, spins up/down smoothly.
///  * Tap → play / pause.
///  * Drag in a circle → scratch sound + scrub (one full turn = [secondsPerTurn]).
class VinylDisc extends StatefulWidget {
  const VinylDisc({
    super.key,
    required this.controller,
    required this.size,
    this.caption,
    this.secondsPerTurn = 15,
  });

  final PlayerController controller;
  final double size;

  /// Small text printed on the label (hidden on small discs).
  final String? caption;
  final double secondsPerTurn;

  @override
  State<VinylDisc> createState() => _VinylDiscState();
}

/// Pan recognizer that wins the gesture arena as soon as a finger lands on the
/// disc, so a parent PageView / ListView can't steal the scratch gesture.
class _EagerPanRecognizer extends PanGestureRecognizer {
  _EagerPanRecognizer({super.debugOwner});

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _VinylDiscState extends State<VinylDisc> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _lastAngle = 0;
  double _travel = 0; // px the finger has moved since touching down
  bool _scrubbing = false;

  void _onStart(DragStartDetails d) {
    _lastAngle = _angleAt(d.localPosition);
    _travel = 0;
    _scrubbing = false;
  }

  void _onUpdate(DragUpdateDetails d) {
    final c = widget.controller;
    _travel += d.delta.distance;
    final a = _angleAt(d.localPosition);
    var delta = a - _lastAngle;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    _lastAngle = a;

    if (!_scrubbing) {
      if (_travel < 8) return; // still could be a tap
      _scrubbing = true;
      c.beginScrub();
    }
    c.rotateDiscBy(delta);
    c.scratch(delta);
    c.scrubBy(Duration(
      milliseconds: (delta / (2 * math.pi) * widget.secondsPerTurn * 1000).round(),
    ));
  }

  void _onEnd() {
    if (_scrubbing) {
      _scrubbing = false;
      widget.controller.endScrub();
    } else {
      widget.controller.toggle(); // it was a tap
    }
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    widget.controller.addListener(_sync);
    _sync();
  }

  // Only animate while the disc is actually turning (saves battery).
  void _sync() {
    if (widget.controller.playing && !_ticker.isActive) _ticker.start();
  }

  void _tick(Duration _) {
    final c = widget.controller;
    c.tickDisc();
    if (!c.discMoving) {
      _ticker.stop();
      c.resetDiscClock();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _ticker.dispose();
    super.dispose();
  }

  double _angleAt(Offset p) {
    final c = widget.size / 2;
    return math.atan2(p.dy - c, p.dx - c);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final track = c.current;
    final s = widget.size;

    return Semantics(
      button: true,
      label: 'Disc. Tap to ${c.playing ? 'pause' : 'play'}, drag to scrub',
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _EagerPanRecognizer: GestureRecognizerFactoryWithHandlers<_EagerPanRecognizer>(
            () => _EagerPanRecognizer(debugOwner: this),
            (r) => r
              ..dragStartBehavior = DragStartBehavior.down
              ..onStart = _onStart
              ..onUpdate = _onUpdate
              ..onEnd = ((_) => _onEnd())
              ..onCancel = () {
                if (_scrubbing) {
                  _scrubbing = false;
                  widget.controller.endScrub();
                }
              },
          ),
        },
        child: SizedBox.square(
          dimension: s,
          child: Stack(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: c.discAngle,
                builder: (_, angle, child) => Transform.rotate(angle: angle, child: child),
                child: RepaintBoundary(
                  child: _DiscFace(
                    size: s,
                    hue: track.hue,
                    initial: track.title.trim().isEmpty ? '♪' : track.title.trim()[0].toUpperCase(),
                    caption: s >= 160 ? widget.caption : null,
                  ),
                ),
              ),
              // Light reflection stays still while the disc turns underneath.
              IgnorePointer(child: CustomPaint(size: Size.square(s), painter: _SheenPainter())),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscFace extends StatelessWidget {
  const _DiscFace({required this.size, required this.hue, required this.initial, this.caption});

  final double size;
  final double hue;
  final String initial;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final label = size * 0.36;
    final big = size >= 160;
    const ink = Color(0xBF140A05);

    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size.square(size), painter: _GroovePainter()),
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            width: label,
            height: label,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF111111), width: big ? 3 : 2),
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.4),
                colors: [NP.label(hue, .62), NP.label(hue, .42), NP.label(hue, .30)],
                stops: const [0, .7, 1],
              ),
              boxShadow: [BoxShadow(color: NP.label(hue, .55).withValues(alpha: .35), blurRadius: big ? 18 : 10)],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (big) // marker dot so you can see the rotation
                  Positioned(
                    top: label * .09,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(color: Color(0x8C140A05), shape: BoxShape.circle),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(0, -label * (big ? .2 : .12)),
                  child: Text(
                    initial,
                    style: TextStyle(fontSize: label * .3, fontWeight: FontWeight.w600, color: ink, height: 1),
                  ),
                ),
                if (caption != null)
                  Positioned(
                    bottom: label * .2,
                    child: Text(
                      caption!,
                      style: TextStyle(
                        fontSize: label * .085,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                        color: const Color(0x99140A05),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Spindle hole
          Container(
            width: big ? 9 : 5,
            height: big ? 9 : 5,
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: .08), width: .8),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;

    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF19191C));

    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xFF0C0C0E);
    for (var rr = r * .36; rr < r * .985; rr += 2.6) {
      canvas.drawCircle(c, rr, groove);
    }

    // Gap between songs (orange tint) and a faint outer ring.
    canvas.drawCircle(
      c,
      r * .66,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = NP.accent.withValues(alpha: .14),
    );
    canvas.drawCircle(
      c,
      r * .95,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: .05),
    );

    // Edge vignette + rim
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: .75)],
          stops: const [.82, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF0A0A0B),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SheenPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: size.width / 2);
    final w1 = Colors.white.withValues(alpha: .09);
    final w2 = Colors.white.withValues(alpha: .06);
    const t = Colors.transparent;
    canvas.drawCircle(
      c,
      size.width / 2,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = SweepGradient(
          colors: [t, w1, t, t, w2, t, t],
          stops: const [0, .06, .15, .5, .57, .66, 1],
          transform: const GradientRotation(-math.pi / 2 + .35),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
