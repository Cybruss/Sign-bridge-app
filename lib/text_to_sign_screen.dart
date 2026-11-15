import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:xml/xml.dart';

class TextToSignScreen extends StatefulWidget {
  const TextToSignScreen({super.key});

  @override
  State<TextToSignScreen> createState() => _TextToSignScreenState();
}

class _TextToSignScreenState extends State<TextToSignScreen> {
  final TextEditingController _textController = TextEditingController();

  WebViewController? _webController;
  HttpServer? _assetServer;
  bool _avatarReady = false;
  bool _lexiconReady = false;
  bool _webViewReady = false;
  String _status = 'Loading sign examples…';

  final Map<String, String> _signByGloss = <String, String>{};

  List<String> _missingTokens = <String>[];

  @override
  void initState() {
    super.initState();
    _initWebView();
    _loadLexicon();
  }

  Future<void> _initWebView() async {
    if (!Platform.isAndroid) {
      if (mounted) {
        setState(
          () => _status = 'Sign examples are currently available on Android.',
        );
      }
      return;
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _assetServer = server;
    server.listen(_serveBundledAsset);

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'AvatarBridge',
        onMessageReceived: (message) {
          if (!mounted) return;
          final msg = message.message;
          debugPrint('AvatarBridge: $msg');
          if (msg == 'ready') {
            setState(() {
              _avatarReady = true;
              _status = _lexiconReady
                  ? 'Ready to show signs.'
                  : 'Loading sign examples…';
            });
          } else if (msg.startsWith('status:')) {
            setState(() => _status = 'Preparing sign player…');
          } else if (msg.startsWith('error:')) {
            setState(() => _status = 'The sign player could not load.');
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _status = 'Loading sign player…';
            });
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _webViewReady = true;
              if (!_avatarReady) {
                _status = 'Preparing sign player…';
              }
            });
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _status =
                  'Could not load the sign player. Check your connection.';
            });
          },
        ),
      );

    await controller.loadRequest(
      Uri.parse(
        'http://127.0.0.1:${server.port}/jas/loc2025/cwa/flutter_player.html',
      ),
    );
    if (!mounted) return;
    setState(() {
      _webController = controller;
    });
  }

  Future<void> _serveBundledAsset(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    final assetPath = segments.join('/');
    if ((request.method != 'GET' && request.method != 'HEAD') ||
        segments.contains('..') ||
        !assetPath.startsWith('jas/loc2025/')) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      request.response.headers.contentLength = bytes.length;
      request.response.headers.contentType = _contentType(assetPath);
      if (request.method == 'GET') request.response.add(bytes);
      await request.response.close();
    } catch (error) {
      debugPrint('Bundled SiGML asset not found: $assetPath ($error)');
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  ContentType _contentType(String path) {
    if (path.endsWith('.html')) {
      return ContentType.html;
    }
    if (path.endsWith('.js')) {
      return ContentType('application', 'javascript');
    }
    if (path.endsWith('.css')) {
      return ContentType('text', 'css');
    }
    if (path.endsWith('.json')) {
      return ContentType.json;
    }
    if (path.endsWith('.sigml') || path.endsWith('.xml')) {
      return ContentType('application', 'xml');
    }
    if (path.endsWith('.jar')) {
      return ContentType('application', 'java-archive');
    }
    if (path.endsWith('.vert') || path.endsWith('.frag')) {
      return ContentType('text', 'plain');
    }
    if (path.endsWith('.png')) {
      return ContentType('image', 'png');
    }
    return ContentType.binary;
  }

  Future<void> _loadLexicon() async {
    try {
      final files = <String>[
        'jas/loc2025/sigml/welkom-ngt.sigml',
        'jas/loc2025/sigml/iTakeMug.sigml',
        'jas/loc2025/sigml/scotland-H.sigml',
        'jas/loc2025/sigml/blenderStory.sigml',
      ];

      for (final path in files) {
        final xmlText = await rootBundle.loadString(path);
        _extractSigns(xmlText);
      }

      if (!mounted) return;
      setState(() {
        _lexiconReady = true;
        _status = _avatarReady
            ? 'Ready to show signs.'
            : 'Preparing sign player…';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Could not load sign examples.';
      });
    }
  }

  void _extractSigns(String xmlText) {
    final document = XmlDocument.parse(xmlText);

    final hnsSigns = document.findAllElements('hns_sign');
    for (final sign in hnsSigns) {
      final gloss = sign.getAttribute('gloss');
      if (gloss == null || gloss.trim().isEmpty) continue;
      _signByGloss[gloss.trim().toUpperCase()] = sign.toXmlString(pretty: true);
    }

    final hamGesturalSigns = document.findAllElements('hamgestural_sign');
    for (final sign in hamGesturalSigns) {
      final gloss = sign.getAttribute('gloss');
      if (gloss == null || gloss.trim().isEmpty) continue;
      _signByGloss[gloss.trim().toUpperCase()] = sign.toXmlString(pretty: true);
    }
  }

  Future<void> _convertAndPlay() async {
    final input = _textController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _status = 'Please enter text first.';
      });
      return;
    }
    if (!_lexiconReady) {
      setState(() {
        _status = 'Lexicon not ready yet. Please wait.';
      });
      return;
    }

    if (!_webViewReady) {
      setState(() {
        _status = 'Player page is not ready yet. Please wait a moment.';
      });
      return;
    }

    final tokens = _tokenize(input);
    final selectedSigns = <String>[];
    final missing = <String>[];

    for (final token in tokens) {
      final gloss = _tokenToGloss(token);
      final sign = _signByGloss[gloss];
      if (sign == null) {
        missing.add(token);
        continue;
      }
      selectedSigns.add(sign);
    }

    if (selectedSigns.isEmpty) {
      setState(() {
        _missingTokens = missing;
        _status =
            'No available signs found. Try welcome, here, I take mug, Scotland, or orange blender explode.';
      });
      return;
    }

    final sigml = _assembleSigml(selectedSigns);

    setState(() {
      _missingTokens = missing;
      _status = missing.isEmpty
          ? 'Playing ${selectedSigns.length} available signs.'
          : 'Playing available signs. No sign found for: ${missing.join(', ')}.';
    });

    if (_avatarReady && _webController != null) {
      final escaped = jsonEncode(sigml);
      await _webController!.runJavaScript('playSigmlFromFlutter($escaped);');
      if (!mounted) return;
      setState(() {
        _status = 'Signs are playing.';
      });
    } else {
      setState(() {
        _status = 'The sign player is still getting ready.';
      });
    }
  }

  List<String> _tokenize(String text) {
    return text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }

  String _tokenToGloss(String token) {
    switch (token) {
      case 'HELLO':
      case 'WELCOME':
        return 'WELKOM';
      case 'HERE':
        return 'HIER';
      case 'I':
        return 'I';
      case 'TAKE':
        return 'TAKE';
      case 'MUG':
        return 'MUG';
      case 'SCOTLAND':
        return 'SCOTLAND-NEW';
      default:
        return token;
    }
  }

  String _assembleSigml(List<String> signBlocks) {
    final content = signBlocks.join('\n\n');
    return '<?xml version="1.0" encoding="utf-8"?>\n<sigml>\n\n$content\n\n</sigml>\n';
  }

  Future<void> _stopAvatar() async {
    if (_webController == null) return;
    await _webController!.runJavaScript('stopSigmlFromFlutter();');
    if (!mounted) return;
    setState(() {
      _status = 'Playback stopped.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Local sign examples')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'This small collection uses Dutch Sign Language examples. '
                    'It plays available words in sequence and does not convert '
                    'English sentence grammar into sign language. Try '
                    '“welcome”, “I take mug”, “Scotland”, or '
                    '“orange blender explode”.',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _textController,
                decoration: InputDecoration(
                  labelText: 'Enter a word or short phrase',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _textController.clear();
                      setState(() {
                        _missingTokens = <String>[];
                        _status = 'Ready to show signs.';
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Browse available words'),
                subtitle: const Text('Tap a word to add it'),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: (_signByGloss.keys.toList()..sort()).map((
                        gloss,
                      ) {
                        return ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(gloss.replaceAll('_', ' ').toLowerCase()),
                          onPressed: () {
                            final current = _textController.text.trim();
                            final word = gloss
                                .replaceAll('_', ' ')
                                .toLowerCase();
                            _textController.text = current.isEmpty
                                ? word
                                : '$current $word';
                            _textController.selection = TextSelection.collapsed(
                              offset: _textController.text.length,
                            );
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _convertAndPlay,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Show signs'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _stopAvatar,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _status,
                  style: TextStyle(
                    color: _status.toLowerCase().contains('error')
                        ? Colors.red
                        : Colors.black87,
                    fontSize: 13,
                  ),
                ),
              ),
              if (_missingTokens.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'No available sign for: ${_missingTokens.join(', ')}',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                height: 360,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _webController == null
                      ? const Center(child: CircularProgressIndicator())
                      : WebViewWidget(controller: _webController!),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _assetServer?.close(force: true);
    super.dispose();
  }
}
