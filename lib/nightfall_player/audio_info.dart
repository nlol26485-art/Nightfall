import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Format, sample rate and bit depth read straight from an audio file's header.
class AudioQuality {
  const AudioQuality({required this.format, this.sampleRate, this.bitDepth});

  final String format;
  final int? sampleRate;
  final int? bitDepth;
}

/// Reads FLAC, WAV, AIFF and ALAC (.m4a) headers. Returns null for other
/// formats (MP3, AAC, OGG...) or if the file can't be read.
Future<AudioQuality?> readAudioQuality(String path) async {
  RandomAccessFile? raf;
  try {
    raf = await File(path).open();
    final len = await raf.length();
    var head = await raf.read(math.min(len, 1 << 16));

    // Some FLAC files start with an ID3 tag; skip it.
    final skip = _id3Size(head);
    if (skip > 0 && skip < len) {
      await raf.setPosition(skip);
      head = await raf.read(math.min(len - skip, 1 << 16));
    }

    final q = _flac(head) ?? _wav(head) ?? _aiff(head);
    if (q != null) return q;

    if (_tag(head, 4, 'ftyp')) {
      // MP4/M4A: the ALAC settings live in the 'moov' box, which can be at
      // the start or the end of the file.
      final fromHead = _alac(head);
      if (fromHead != null) return fromHead;
      if (_contains(head, 'mp4a')) return const AudioQuality(format: 'AAC'); // lossy, no need to look further
      if (len > head.length) {
        final tailLen = math.min(len, 4 << 20);
        await raf.setPosition(len - tailLen);
        return _alac(await raf.read(tailLen));
      }
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    await raf?.close();
  }
}

/// Best guess from the file extension, used when the header says nothing.
String? formatFromName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  switch (name.substring(dot + 1).toLowerCase()) {
    case 'flac':
      return 'FLAC';
    case 'wav':
      return 'WAV';
    case 'aif':
    case 'aiff':
    case 'aifc':
      return 'AIFF';
    case 'mp3':
      return 'MP3';
    case 'm4a':
    case 'aac':
    case 'mp4':
      return 'AAC';
    case 'ogg':
    case 'oga':
      return 'OGG';
    case 'opus':
      return 'OPUS';
    default:
      return null;
  }
}

// ------------------------------------------------------------------ parsers

AudioQuality? _flac(Uint8List b) {
  // "fLaC", 4-byte block header, then STREAMINFO.
  if (!_tag(b, 0, 'fLaC') || b.length < 8 + 18) return null;
  const s = 8;
  final rate = (b[s + 10] << 12) | (b[s + 11] << 4) | (b[s + 12] >> 4);
  final bits = (((b[s + 12] & 0x01) << 4) | (b[s + 13] >> 4)) + 1;
  return AudioQuality(format: 'FLAC', sampleRate: rate, bitDepth: bits);
}

AudioQuality? _wav(Uint8List b) {
  if (!(_tag(b, 0, 'RIFF') || _tag(b, 0, 'RF64')) || !_tag(b, 8, 'WAVE')) return null;
  var o = 12;
  while (o + 8 <= b.length) {
    final size = _u32le(b, o + 4);
    if (_tag(b, o, 'fmt ') && o + 24 <= b.length) {
      return AudioQuality(format: 'WAV', sampleRate: _u32le(b, o + 12), bitDepth: _u16le(b, o + 22));
    }
    o += 8 + size + (size & 1);
  }
  return const AudioQuality(format: 'WAV');
}

AudioQuality? _aiff(Uint8List b) {
  if (!_tag(b, 0, 'FORM') || !(_tag(b, 8, 'AIFF') || _tag(b, 8, 'AIFC'))) return null;
  var o = 12;
  while (o + 8 <= b.length) {
    final size = _u32be(b, o + 4);
    if (_tag(b, o, 'COMM') && o + 26 <= b.length) {
      return AudioQuality(format: 'AIFF', sampleRate: _extended(b, o + 16), bitDepth: _u16be(b, o + 14));
    }
    o += 8 + size + (size & 1);
  }
  return const AudioQuality(format: 'AIFF');
}

AudioQuality? _alac(Uint8List b) {
  var seen = false;
  for (var o = 4; o + 32 <= b.length; o++) {
    if (b[o] != 0x61 || !_tag(b, o, 'alac')) continue; // 0x61 = 'a'
    seen = true;
    // The 36-byte 'alac' box holds the decoder config:
    // size, 'alac', version/flags, frameLength(4), compat(1), bitDepth(1), ..., sampleRate(4)
    if (_u32be(b, o - 4) == 36) {
      final c = o + 8;
      return AudioQuality(format: 'ALAC', sampleRate: _u32be(b, c + 20), bitDepth: b[c + 5]);
    }
  }
  return seen ? const AudioQuality(format: 'ALAC') : null;
}

// ------------------------------------------------------------------ helpers

int _id3Size(Uint8List b) {
  if (b.length < 10 || !_tag(b, 0, 'ID3')) return 0;
  final size = ((b[6] & 0x7f) << 21) | ((b[7] & 0x7f) << 14) | ((b[8] & 0x7f) << 7) | (b[9] & 0x7f);
  final footer = (b[5] & 0x10) != 0 ? 10 : 0;
  return 10 + size + footer;
}

bool _contains(Uint8List b, String s) {
  final first = s.codeUnitAt(0);
  for (var o = 0; o + s.length <= b.length; o++) {
    if (b[o] == first && _tag(b, o, s)) return true;
  }
  return false;
}

bool _tag(Uint8List b, int o, String s) {
  if (o < 0 || o + s.length > b.length) return false;
  for (var i = 0; i < s.length; i++) {
    if (b[o + i] != s.codeUnitAt(i)) return false;
  }
  return true;
}

int _u16be(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
int _u32be(Uint8List b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
int _u16le(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
int _u32le(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

/// AIFF stores the sample rate as an 80-bit float.
int _extended(Uint8List b, int o) {
  final exponent = ((b[o] & 0x7f) << 8) | b[o + 1];
  final top = _u32be(b, o + 2); // top 32 bits of the mantissa
  final shift = exponent - 16383 - 31;
  if (shift >= 0) return shift > 31 ? 0 : top << shift;
  return -shift > 63 ? 0 : top >> -shift;
}
