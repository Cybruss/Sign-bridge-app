import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AslDictionaryScreen extends StatefulWidget {
  const AslDictionaryScreen({super.key});

  @override
  State<AslDictionaryScreen> createState() => _AslDictionaryScreenState();
}

class _AslDictionaryScreenState extends State<AslDictionaryScreen> {
  static final Uri _dictionaryUri = Uri.parse(
    'https://www.signasl.org/sign/search',
  );
  late final WebViewController _controller;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _error = null);
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame != false) {
              setState(() => _error = error.description);
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null || uri.scheme != 'https') {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(_dictionaryUri);
  }

  Future<void> _reload() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ASL Video Dictionary'),
        actions: [
          IconButton(
            tooltip: 'Reload dictionary',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.school_outlined, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Look up a sign video, practice it, then return to the camera. This learning reference is hosted by SignASL and needs internet.',
                      style: TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_progress < 100)
            LinearProgressIndicator(
              value: _progress == 0 ? null : _progress / 100,
            ),
          if (_error != null)
            MaterialBanner(
              content: Text('Could not load the dictionary: $_error'),
              leading: const Icon(Icons.wifi_off_rounded),
              actions: [
                TextButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
