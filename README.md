# Nightfall

A dark, neumorphic music player for Android, built with Flutter. Its centrepiece is a vinyl disc you can spin and scratch.

## Download

Get the latest **`nightfall.apk`** from the [Releases page](../../releases/latest), open it on your Android phone, and allow *install unknown apps* when asked.

## Features

- **Interactive vinyl disc.** Tap to play or pause. Drag it in a circle to scratch, with real scratch sounds and a vibration tick, and to scrub through the song.
- **Your music, found automatically.** After you allow music access, the app finds songs in Music, Download, Documents, Podcasts and Audiobooks, and picks up new ones every time it opens. You can also add files by hand with **+**.
- **Hi-res aware.** FLAC, WAV, AIFF and ALAC files show their real quality (for example *FLAC · 24-bit · 96 kHz*) with a **HI-RES** or **LOSSLESS** badge.
- **Playlists.** Create, rename and delete playlists, and add songs from any song's ⋮ menu. Everything is saved.
- **Equalizer.** Uses the phone's built-in bands, with presets (Bass boost, Vocal, Rock, Pop…) and a volume boost.
- **Listening stats.** Listening time, plays, most played, recently played, and library size and storage.
- **The basics:** shuffle, repeat (all / one), sleep timer, likes, and an on/off switch for the scratch sound and vibration.

## Build it yourself

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable), Android Studio or the Android SDK, and **Java 17**.

```bash
git clone https://github.com/nlol26485-art/Nightfall.git
cd Nightfall
flutter pub get
flutter run                     # on a phone with USB debugging on
flutter build apk --release     # → build/app/outputs/flutter-apk/app-release.apk
```

**Troubleshooting**

- **"Java … incompatible with Gradle":** install JDK 17 and run `flutter config --jdk-dir="<path to jdk-17>"`.
- **Android build errors after a Flutter upgrade:** run `flutter create --platforms=android --org com.yajat --project-name nightfall .` to refresh the Android files. It doesn't touch `lib/`.

## Making a release

Every push to `main` is built by GitHub Actions; the APK appears under the run's *Artifacts*. To publish a download for everyone, push a version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow then creates a GitHub Release with `nightfall.apk` attached.

## Code map

```
lib/main.dart                         app setup
lib/nightfall_player/
  player_controller.dart              playback, queue, library, playlists, EQ, stats
  vinyl_disc.dart                     the interactive disc
  scratch_sound.dart                  scratch samples (assets/sfx/)
  now_playing_screen.dart             Playing Now screen
  playlist_screen.dart                Library: Songs + Playlists tabs
  settings_screen.dart                Settings
  equalizer_screen.dart               Equalizer
  stats_screen.dart                   Listening stats
  music_scanner.dart                  finds songs on the phone
  importer.dart                       + button: copy files into the app
  audio_info.dart                     reads bit depth / sample rate
  library_store.dart                  saves everything to library.json
  settings.dart                       settings, EQ presets, stats models
  widgets.dart, theme.dart            buttons, seek bar, tonearm, colours
```

## License

[MIT](LICENSE)
