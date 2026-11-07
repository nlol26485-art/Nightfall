import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'player_controller.dart';
import 'settings.dart';
import 'settings_screen.dart';
import 'theme.dart';

/// The phone's built-in equalizer (usually 5 bands), presets and a volume boost.
class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  AndroidEqualizerParameters? _params;
  bool _loading = true;
  late double _boost = widget.controller.settings.boostDb;

  PlayerController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.equalizerParameters().then((p) {
      if (mounted) {
        setState(() {
          _params = p;
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return NFPage(
      title: 'EQUALIZER',
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final s = c.settings;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              NFSection(title: 'EQUALIZER', children: [
                NFSwitchRow(
                  icon: Icons.equalizer_rounded,
                  title: 'Equalizer',
                  subtitle: s.eqEnabled ? 'On · ${s.eqPreset}' : 'Off',
                  value: s.eqEnabled,
                  onChanged: c.setEqEnabled,
                ),
              ]),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator(color: NP.accent)),
                )
              else if (_params == null)
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 28, 12, 0),
                  child: Text(
                    'The equalizer starts once a song has been loaded.\nPlay any song, then open this page again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: NP.muted, height: 1.5),
                  ),
                )
              else ...[
                NFSection(title: 'PRESETS', children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in eqPresets)
                          _Chip(
                            label: p,
                            selected: s.eqEnabled && s.eqPreset == p,
                            onTap: () => c.applyEqPreset(p),
                          ),
                        if (s.eqPreset == 'Custom')
                          _Chip(label: 'Custom', selected: s.eqEnabled, onTap: () => c.setEqEnabled(true)),
                      ],
                    ),
                  ),
                ]),
                NFSection(title: 'BANDS', children: [_bands(_params!, enabled: s.eqEnabled)]),
              ],
              NFSection(title: 'VOLUME BOOST', children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.volume_up_rounded, size: 20, color: NP.muted),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text('Louder quiet songs',
                            style: TextStyle(fontSize: 13.5, color: NP.text, fontWeight: FontWeight.w500)),
                      ),
                      Text(_boost == 0 ? 'Off' : '+${_boost.toStringAsFixed(1)} dB',
                          style: const TextStyle(fontSize: 12, color: NP.accent2)),
                    ],
                  ),
                ),
                _slider(
                  value: _boost,
                  min: 0,
                  max: 10,
                  onChanged: (v) => setState(() => _boost = v),
                  onChangeEnd: c.setBoost,
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text('Keep this low on headphones; high boost can distort.',
                      style: TextStyle(fontSize: 10.5, color: NP.faint)),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _bands(AndroidEqualizerParameters p, {required bool enabled}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
      child: Row(
        children: [
          for (var i = 0; i < p.bands.length; i++)
            Expanded(
              child: StreamBuilder<double>(
                stream: p.bands[i].gainStream,
                initialData: p.bands[i].gain,
                builder: (context, snap) {
                  final g = (snap.data ?? 0).clamp(p.minDecibels, p.maxDecibels).toDouble();
                  return Opacity(
                    opacity: enabled ? 1 : .45,
                    child: Column(
                      children: [
                        Text('${g > 0 ? '+' : ''}${g.toStringAsFixed(1)}',
                            style: const TextStyle(fontSize: 10, color: NP.muted)),
                        SizedBox(
                          height: 170,
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: _slider(
                              value: g,
                              min: p.minDecibels,
                              max: p.maxDecibels,
                              onChanged: (v) => p.bands[i].setGain(v),
                              onChangeEnd: (v) {
                                c.setEqGain(i, v);
                                if (!c.settings.eqEnabled) c.setEqEnabled(true);
                              },
                            ),
                          ),
                        ),
                        Text(_hz(p.bands[i].centerFrequency),
                            style: const TextStyle(fontSize: 10, color: NP.faint)),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _slider({
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: NP.accent,
        inactiveTrackColor: NP.dark,
        thumbColor: NP.accent2,
        overlayColor: NP.accent.withValues(alpha: .15),
      ),
      child: Slider(
        value: value.clamp(min, max).toDouble(),
        min: min,
        max: max,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }

  static String _hz(double hz) {
    if (hz < 1000) return '${hz.round()}';
    final k = hz / 1000;
    return '${k < 10 ? k.toStringAsFixed(1) : k.round()}k';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: selected ? NP.playGradient : NP.insetGradient,
          boxShadow: selected ? NP.accentGlow(10, .35) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : NP.muted,
          ),
        ),
      ),
    );
  }
}
