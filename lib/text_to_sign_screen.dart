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
  String _status = 'Loading avatar + SiGML lexicon...';

  final Map<String, String> _signByGloss = <String, String>{};

  String _hamnosysPreview = '';
  String _sigmlPreview = '';
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
          () =>
              _status = 'The bundled SiGML player currently requires Android.',
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
                  ? 'Avatar ready. Enter text and press Convert.'
                  : 'Avatar ready. Waiting for lexicon...';
            });
          } else if (msg.startsWith('status:')) {
            setState(() {
              _status = 'Avatar: ${msg.substring(7)}';
            });
          } else if (msg.startsWith('error:')) {
            setState(() {
              _status = 'Avatar error: ${msg.substring(6)}';
            });
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _status = 'Loading player: $url';
            });
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _webViewReady = true;
              if (!_avatarReady) {
                _status = 'Player loaded, waiting avatar init...';
              }
            });
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _status = 'WebView error: ${error.description}';
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
            ? 'Ready. Enter text and press Convert.'
            : 'Lexicon loaded. Waiting for avatar...';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Failed to load SiGML lexicon: $e';
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
    final hamnosysRows = <String>[];
    final missing = <String>[];

    for (final token in tokens) {
      final gloss = _tokenToGloss(token);
      final sign = _signByGloss[gloss];
      if (sign == null) {
        missing.add(token);
        continue;
      }
      selectedSigns.add(sign);
      hamnosysRows.add(_buildHamnosysTrace(gloss, sign));
    }

    if (selectedSigns.isEmpty) {
      setState(() {
        _missingTokens = missing;
        _hamnosysPreview = '';
        _sigmlPreview = '';
        _status =
            'No matching signs found in current lexicon. Try: welcome, here, i, take, mug, scotland.';
      });
      return;
    }

    final sigml = _assembleSigml(selectedSigns);

    setState(() {
      _missingTokens = missing;
      _hamnosysPreview = hamnosysRows.join('\n\n');
      _sigmlPreview = sigml;
      _status = 'Converted text to SiGML (${selectedSigns.length} sign(s)).';
    });

    if (_avatarReady && _webController != null) {
      final escaped = jsonEncode(sigml);
      await _webController!.runJavaScript('playSigmlFromFlutter($escaped);');
      if (!mounted) return;
      setState(() {
        _status = 'Playing on avatar...';
      });
    } else {
      setState(() {
        _status = 'SiGML generated. Avatar is not ready yet.';
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

  String _buildHamnosysTrace(String gloss, String signXml) {
    final lower = signXml.toLowerCase();
    final isHns = lower.contains('<hamnosys_manual>');
    final manualTags = <String>[];

    if (isHns) {
      final manualRegex = RegExp(
        r'<hamnosys_manual>([\s\S]*?)</hamnosys_manual>',
        caseSensitive: false,
      );
      final match = manualRegex.firstMatch(signXml);
      if (match != null) {
        final part = match.group(1) ?? '';
        final tagRegex = RegExp(r'<([a-zA-Z0-9_]+)\b');
        for (final t in tagRegex.allMatches(part)) {
          manualTags.add(t.group(1) ?? '');
        }
      }
    }

    final compact = manualTags.where((e) => e.isNotEmpty).take(16).join('  ');
    if (compact.isEmpty) {
      return '[$gloss]\nManual trace not extracted (non-HamNoSys style sign block).';
    }
    return '[$gloss]\n$compact';
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
      appBar: AppBar(title: const Text('Text to Sign · SiGML examples')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Experimental local demo: this bundled lexicon contains '
                    'limited NGT example signs. It matches supported glosses '
                    'and joins their SiGML blocks; it does not translate '
                    'English grammar or produce ASL. Try “welcome”, “I take '
                    'mug”, “Scotland”, or “orange blender explode”.',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _textController,
                decoration: InputDecoration(
                  labelText: 'Enter text (example: I take mug)',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _textController.clear();
                      setState(() {
                        _hamnosysPreview = '';
                        _sigmlPreview = '';
                        _missingTokens = <String>[];
                        _status = 'Cleared.';
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Browse ${_signByGloss.length} bundled glosses'),
                subtitle: const Text('Tap a gloss to add it to the input'),
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
                      label: const Text('Convert + Play'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _stopAvatar,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop Avatar'),
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
                      'Missing tokens in current lexicon: ${_missingTokens.join(', ')}',
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
              const SizedBox(height: 10),
              SizedBox(
                height: 260,
                child: Row(
                  children: [
                    Expanded(
                      child: _buildPreviewPanel(
                        title: 'HamNoSys trace (when present)',
                        content: _hamnosysPreview.isEmpty
                            ? 'The bundled examples use SiGML hamgestural_sign blocks. A HamNoSys manual trace appears only when that markup is present.'
                            : _hamnosysPreview,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildPreviewPanel(
                        title: 'Generated SiGML',
                        content: _sigmlPreview.isEmpty
                            ? 'Generated SiGML will appear here.'
                            : _sigmlPreview,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewPanel({required String title, required String content}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SelectableText(
            content,
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
        ],
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
