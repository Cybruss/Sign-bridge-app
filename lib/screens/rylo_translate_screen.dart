import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Opens Rylo Translate as an online text-to-sign fallback.
///
/// Translation is performed by the remote service. This app does not bundle
/// Rylo models or send text until the user enters it into the loaded page.
class RyloTranslateScreen extends StatefulWidget {
  const RyloTranslateScreen({super.key});

  @override
  State<RyloTranslateScreen> createState() => _RyloTranslateScreenState();
}

class _RyloTranslateScreenState extends State<RyloTranslateScreen> {
  static final Uri _translateUri = Uri.parse(
    'https://rylo.com/sign/translate/?sil=ase&spl=en',
  );

  late final WebViewController _controller;
  int _progress = 0;
  String? _pageError;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _progress = 0;
              _pageError = null;
            });
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _progress = 100);
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame == false) return;
            setState(() => _pageError = error.description);
          },
          onHttpError: (error) {
            if (!mounted) return;
            final statusCode = error.response?.statusCode;
            if (statusCode != null && statusCode >= 400) {
              setState(
                () => _pageError = 'Rylo Translate returned HTTP $statusCode.',
              );
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
      );
    unawaited(_controller.loadRequest(_translateUri));
  }

  Future<void> _reload() async {
    setState(() {
      _pageError = null;
      _progress = 0;
    });
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rylo Translate'),
        actions: [
          IconButton(
            tooltip: 'Reload translator',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
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
                  Icon(Icons.cloud_outlined, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Online fallback (English → ASL). Text you enter on the '
                      'Rylo page is sent to its service. Availability and '
                      'translation are controlled by Rylo.',
                      style: TextStyle(fontSize: 12),
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
          if (_pageError != null)
            MaterialBanner(
              content: Text('Could not load the translator: $_pageError'),
              leading: const Icon(Icons.wifi_off),
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
