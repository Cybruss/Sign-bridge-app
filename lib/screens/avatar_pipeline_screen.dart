import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';

class AvatarPipelineScreen extends StatefulWidget {
  const AvatarPipelineScreen({super.key});

  @override
  State<AvatarPipelineScreen> createState() => _AvatarPipelineScreenState();
}

class _AvatarPipelineScreenState extends State<AvatarPipelineScreen> {
  final Flutter3DController _controller = Flutter3DController();
  final TextEditingController _textController = TextEditingController();

  String status = "Enter a sentence";
  bool isPlaying = false;

  String originalSentence = "";
  List<String> tokens = [];
  List<String> filteredTokens = [];
  List<String> glossOutput = [];

  final List<String> stopWords = [
    "to",
    "is",
    "am",
    "are",
    "the",
    "a",
    "an",
    "of",
    "in",
  ];

  final Map<String, String> glossMap = {
    "i": "ME",
    "me": "ME",
    "want": "WANT",
    "eat": "EAT",
    "pizza": "PIZZA",
    "cake": "CAKE",
    "and": "AND",
  };

  List<String> processSentence(String sentence) {
    originalSentence = sentence;
    sentence = sentence.toLowerCase();
    tokens = sentence.split(RegExp(r'\s+'));
    filteredTokens = List.from(tokens);
    filteredTokens.removeWhere((word) => stopWords.contains(word));
    List<String> gloss = [];
    for (String word in filteredTokens) {
      if (glossMap.containsKey(word)) gloss.add(glossMap[word]!);
    }
    glossOutput = gloss;
    return gloss;
  }

  Future<void> playGlossSequence(List<String> glossWords) async {
    if (isPlaying) return;
    isPlaying = true;
    for (String word in glossWords) {
      if (!isPlaying) break;
      setState(() {
        status = "Playing: $word";
      });
      _controller.pauseAnimation();
      await Future.delayed(const Duration(milliseconds: 200));
      _controller.playAnimation(animationName: word);
      await Future.delayed(const Duration(milliseconds: 1800));
    }
    _controller.pauseAnimation();
    isPlaying = false;
    setState(() {
      status = "Done";
    });
  }

  void translateAndPlay() {
    if (isPlaying) stopAnimation();
    String input = _textController.text.trim();
    if (input.isEmpty) {
      setState(() => status = "Please enter a sentence");
      return;
    }
    List<String> gloss = processSentence(input);
    setState(() {
      status = gloss.join(" ");
    });
    playGlossSequence(gloss);
  }

  void stopAnimation() {
    isPlaying = false;
    _controller.pauseAnimation();
    setState(() {
      status = "Stopped";
    });
  }

  @override
  void initState() {
    super.initState();
    _verifyAsset();
  }

  Future<void> _verifyAsset() async {
    try {
      await rootBundle.load('avatars/AmyAvatarnew.glb');
      if (!mounted) return;
      setState(() {
        status = "Ready. Enter text and press Translate.";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        status = "Asset error: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Text("ASL Translator"),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF16213E),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Flutter3DViewer(
                src: 'avatars/AmyAvatarnew.glb',
                controller: _controller,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _textController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Enter sentence...",
                filled: true,
                fillColor: const Color(0xFF16213E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: translateAndPlay,
                  child: const Text("Translate"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: stopAnimation,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text("Stop"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(status),
          const SizedBox(height: 10),
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueAccent),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Pipeline Debug:",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent)),
                const SizedBox(height: 6),
                Text("Original: $originalSentence"),
                Text("Tokens: $tokens"),
                Text("Filtered: $filteredTokens"),
                Text("Gloss: $glossOutput"),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
