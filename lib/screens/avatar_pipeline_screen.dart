import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';

/// Plays supported word and phrase clips embedded in the avatar model.
class AvatarPipelineScreen extends StatefulWidget {
  const AvatarPipelineScreen({super.key});

  @override
  State<AvatarPipelineScreen> createState() => _AvatarPipelineScreenState();
}

class _AvatarPipelineScreenState extends State<AvatarPipelineScreen> {
  final Flutter3DController _controller = Flutter3DController();
  final TextEditingController _textController = TextEditingController();

  static const Map<String, String> _legacyClipAliases = {
    'i': 'ME',
    'me': 'ME',
    'want': 'WANT',
    'eat': 'EAT',
    'pizza': 'PIZZA',
    'cake': 'CAKE',
    'and': 'AND',
  };

  Set<String> _availableAnimations = {};
  Map<String, String> _clipByWord = {};
  List<String> _matchedClips = [];
  List<String> _unsupportedWords = [];
  String _status = 'Loading the avatar…';
  String? _avatarPath;
  bool _modelReady = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _prepareAvatarFile();
  }

  Future<void> _prepareAvatarFile() async {
    try {
      final output = File('${Directory.systemTemp.path}/amy_avatar_v2.glb');
      const expectedBytes = 141894668;
      if (!await output.exists() || await output.length() != expectedBytes) {
        final data = await rootBundle.load(
          'assets/avatars/AmyAvatarnew.glb.gz',
        );
        final compressed = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final sink = output.openWrite();
        try {
          await sink.addStream(gzip.decoder.bind(Stream.value(compressed)));
        } finally {
          await sink.close();
        }
        if (await output.length() != expectedBytes) {
          await output.delete();
          throw const FormatException('The avatar file is incomplete.');
        }
      }
      if (!mounted) return;
      setState(() {
        _avatarPath = output.uri.toString();
        _status = 'Avatar ready. Loading animation clips…';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Could not prepare avatar: $error');
    }
  }

  Future<void> _onAvatarLoaded() async {
    try {
      final clips = await _controller.getAvailableAnimations();
      if (!mounted) return;
      final clipByWord = <String, String>{};
      for (final clip in clips) {
        final normalized = _normalizeClip(clip);
        if (normalized.isEmpty) continue;
        // Prefer a plain lowercase clip when duplicate case/slot variants exist.
        if (!clipByWord.containsKey(normalized) || clip == normalized) {
          clipByWord[normalized] = clip;
        }
      }
      setState(() {
        _availableAnimations = clips.toSet();
        _clipByWord = clipByWord;
        _modelReady = true;
        _status = clips.isEmpty
            ? 'Avatar loaded, but no animation clips are available.'
            : 'Ready. ${clipByWord.length} word and phrase clips are available.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Could not read avatar clips: $error');
    }
  }

  List<String> _tokenize(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9']+"), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();

  String _normalizeClip(String clip) => clip
      .replaceFirst(RegExp(r'-Slot(?:\.\d+)?$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\.\d+$'), '')
      .trim()
      .toLowerCase();

  List<String> _matchClips(List<String> tokens) {
    final matches = <String>[];
    final unsupported = <String>[];
    var i = 0;
    while (i < tokens.length) {
      String? match;
      var matchLength = 0;
      // Prefer a full phrase clip (e.g. "all day") over separate words.
      for (var length = tokens.length - i; length > 0; length--) {
        final phrase = tokens.sublist(i, i + length).join(' ');
        final clip = _legacyClipAliases[phrase] ?? _clipByWord[phrase];
        if (clip != null && _availableAnimations.contains(clip)) {
          match = clip;
          matchLength = length;
          break;
        }
      }
      if (match == null) {
        unsupported.add(tokens[i]);
        i++;
      } else {
        matches.add(match);
        i += matchLength;
      }
    }
    _unsupportedWords = unsupported;
    return matches;
  }

  Future<void> _playInput() async {
    if (!_modelReady) {
      setState(() => _status = 'Wait for the avatar to load before playback.');
      return;
    }
    final input = _textController.text.trim();
    if (input.isEmpty) {
      setState(() => _status = 'Enter one or more words first.');
      return;
    }

    final tokens = _tokenize(input);
    final matched = _matchClips(tokens);
    final unsupported = _unsupportedWords;

    setState(() {
      _matchedClips = matched;
      _unsupportedWords = unsupported.toSet().toList();
      _status = matched.isEmpty
          ? 'No supported animation clips were found.'
          : 'Playing ${matched.length} word clip(s).'
                '${unsupported.isEmpty ? '' : ' No clip for: ${unsupported.toSet().join(', ')}.'}';
    });
    if (matched.isEmpty) return;

    setState(() => _isPlaying = true);
    try {
      for (final clip in matched) {
        if (!mounted || !_isPlaying) break;
        setState(() => _status = 'Playing clip: $clip');
        _controller.pauseAnimation();
        _controller.playAnimation(animationName: clip, loopCount: 1);
        await Future<void>.delayed(const Duration(milliseconds: 1800));
      }
      if (mounted && _isPlaying) {
        setState(() => _status = 'Playback finished.');
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'Playback failed: $error');
    } finally {
      _controller.pauseAnimation();
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  void _stopPlayback() {
    _controller.pauseAnimation();
    setState(() {
      _isPlaying = false;
      _status = 'Playback stopped.';
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text('Word animations'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1C22),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: _avatarPath == null
                    ? Center(child: Text(_status, textAlign: TextAlign.center))
                    : Flutter3DViewer(
                        // Flutter serves this asset under the key declared in
                        // pubspec.yaml, including the leading `assets/` segment.
                        src: _avatarPath!,
                        controller: _controller,
                        onLoad: (_) => _onAvatarLoaded(),
                        onError: (error) {
                          if (mounted) {
                            setState(
                              () => _status = 'Avatar load failed: $error',
                            );
                          }
                        },
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _textController,
                style: const TextStyle(color: Color(0xFF2A2620)),
                decoration: InputDecoration(
                  hintText: 'Try: I want pizza',
                  hintStyle: const TextStyle(color: Color(0xFF7A7064)),
                  filled: true,
                  fillColor: colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _modelReady && !_isPlaying ? _playInput : null,
                      child: const Text('Play supported words'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isPlaying ? _stopPlayback : null,
                      child: const Text('Stop'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_status, style: TextStyle(color: colors.onSurface)),
                  const SizedBox(height: 4),
                  Text(
                    'Available signs: ${_matchedClips.length}${_unsupportedWords.isEmpty ? '' : '\nNo sign found for: ${_unsupportedWords.join(', ')}'}',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Avatar dictionary: ${_clipByWord.length} words and phrases. Matching clips play in order; this does not translate sentence grammar.',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
