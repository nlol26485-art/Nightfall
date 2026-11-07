import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'nightfall_player/nightfall_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF141518),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const NightfallApp());
}

class NightfallApp extends StatefulWidget {
  const NightfallApp({super.key});

  @override
  State<NightfallApp> createState() => _NightfallAppState();
}

class _NightfallAppState extends State<NightfallApp> {
  final player = PlayerController(); // starts empty; tap + to add songs
  final pages = PageController();

  void _goTo(int page) =>
      pages.animateToPage(page, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    // Pick up new songs on the phone each time the app opens (Settings → Library).
    player.ready.then((_) {
      if (mounted && player.settings.autoScan) scanPhoneForMusic(player);
    });
  }

  @override
  void dispose() {
    player.dispose();
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    return MaterialApp(
      title: 'Nightfall',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: NP.bg,
        textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(bodyColor: NP.text, displayColor: NP.text),
        colorScheme: base.colorScheme.copyWith(primary: NP.accent, surface: NP.card),
      ),
      home: Scaffold(
        backgroundColor: NP.bg,
        body: PageView(
          controller: pages,
          children: [
            NowPlayingScreen(controller: player, onOpenPlaylist: () => _goTo(1)),
            PlaylistScreen(
              controller: player,
              onBack: () => _goTo(0),
              onImport: () => importAudioFiles(player),
            ),
          ],
        ),
      ),
    );
  }
}
