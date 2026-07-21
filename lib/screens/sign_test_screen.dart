import 'package:flutter/material.dart';
import '../models/prediction.dart';
import '../services/sign_bridge_inference.dart';

class SignTestScreen extends StatefulWidget {
  const SignTestScreen({super.key});

  @override
  State<SignTestScreen> createState() => _SignTestScreenState();
}

class _SignTestScreenState extends State<SignTestScreen> {
  SignBridgeInference? _svc;
  String _status = 'Not initialized';
  List<Prediction> _preds = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _status = 'Loading model...');
    try {
      _svc = await SignBridgeInference.create();
      setState(() => _status = 'Model loaded');
    } catch (e) {
      setState(() => _status = 'Load failed: $e');
    }
  }

  Future<void> _runDummy() async {
    if (_svc == null) return;
    setState(() => _status = 'Running inference on zero input...');
    final frames = List.generate(64, (_) => List.generate(180, (_) => [0.0, 0.0, 0.0]));
    final res = _svc!.predict(frames);
    setState(() {
      _preds = res;
      _status = 'Done';
    });
  }

  @override
  void dispose() {
    _svc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign Inference Test')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text('Status: $_status'),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _runDummy, child: const Text('Run dummy inference')),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _preds.length,
                itemBuilder: (context, i) {
                  final p = _preds[i];
                  return ListTile(
                    title: Text(p.word),
                    subtitle: LinearProgressIndicator(value: p.confidence),
                    trailing: Text((p.confidence * 100).toStringAsFixed(1) + '%'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
