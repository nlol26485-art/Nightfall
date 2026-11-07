import 'package:flutter/material.dart';

/// Colours and neumorphic helpers for the Nightfall player.
class NP {
  NP._();

  static const bg = Color(0xFF131417);
  static const card = Color(0xFF1A1B1E);
  static const dark = Color(0xFF0C0C0E); // shadow side
  static const light = Color(0xFF232428); // highlight side
  static const text = Color(0xFFECECEC);
  static const muted = Color(0xFF7C7E86);
  static const faint = Color(0xFF55575E);
  static const accent = Color(0xFFFF5A1F);
  static const accent2 = Color(0xFFFF8A3D);

  /// Full-screen background.
  static const screenGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1C1D21), Color(0xFF141518)],
  );

  /// Surface of a raised (popped-out) element.
  static const raisedGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1D1E22), Color(0xFF16171A)],
  );

  /// Surface of a pressed-in (inset) element. Flutter has no inset shadows,
  /// so a dark-to-light gradient fakes the sunken look.
  static const insetGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0C0C0E), Color(0xFF18191C)],
  );

  /// Orange play-button surface.
  static const playGradient = RadialGradient(
    center: Alignment(-0.3, -0.4),
    colors: [Color(0xFFFF9A5C), Color(0xFFF24A12), Color(0xFFC93A0C)],
    stops: [0, 0.7, 1],
  );

  /// Dark shadow bottom-right + light shadow top-left = raised neumorphic look.
  static List<BoxShadow> raised(double depth) => [
        BoxShadow(color: dark, offset: Offset(depth, depth), blurRadius: depth * 2),
        BoxShadow(color: light, offset: Offset(-depth * .8, -depth * .8), blurRadius: depth * 1.8),
      ];

  static List<BoxShadow> accentGlow(double blur, [double alpha = .5]) =>
      [BoxShadow(color: accent.withValues(alpha: alpha), blurRadius: blur)];

  /// Disc label colour for a given hue (0–360) and lightness (0–1).
  static Color label(double hue, double lightness) =>
      HSLColor.fromAHSL(1, hue, .92, lightness).toColor();

  static const eyebrow = TextStyle(
    fontSize: 10,
    letterSpacing: 2.5,
    color: muted,
    fontWeight: FontWeight.w500,
  );

  static String time(Duration d) {
    final s = d.inSeconds < 0 ? 0 : d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
