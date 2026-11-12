import 'package:flutter/material.dart';

import 'asl_dictionary_screen.dart';
import 'avatar_pipeline_screen.dart';
import 'rylo_translate_screen.dart';
import '../text_to_sign_screen.dart';

class TextToSignHubScreen extends StatelessWidget {
  const TextToSignHubScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Text to Sign')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Text(
              'Choose how to view a sign',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Try the on-device examples first. The hosted translator needs an internet connection.',
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 22),
            _OptionCard(
              icon: Icons.accessibility_new_rounded,
              title: 'Local word avatar',
              description:
                  'Enter a short phrase. The avatar plays only the word clips available in this demo.',
              badge: 'OFFLINE',
              color: const Color(0xFF4962A8),
              onTap: () => _open(context, const AvatarPipelineScreen()),
            ),
            const SizedBox(height: 12),
            _OptionCard(
              icon: Icons.animation_rounded,
              title: 'Prepared SiGML examples',
              description:
                  'Convert supported words from the bundled lexicon and play them on the local avatar.',
              badge: 'BUNDLED',
              color: const Color(0xFF8D5C32),
              onTap: () => _open(context, const TextToSignScreen()),
            ),
            const SizedBox(height: 12),
            _OptionCard(
              icon: Icons.language_rounded,
              title: 'Online translation fallback',
              description:
                  'Open Rylo’s hosted English-to-ASL translator. Text is sent to that service.',
              badge: 'INTERNET',
              color: const Color(0xFF7052A1),
              onTap: () => _open(context, const RyloTranslateScreen()),
            ),
            const SizedBox(height: 12),
            _OptionCard(
              icon: Icons.school_outlined,
              title: 'Learn a sign by video',
              description:
                  'Search a hosted ASL video dictionary before trying a sign with the camera.',
              badge: 'LEARNING',
              color: const Color(0xFF147D78),
              onTap: () => _open(context, const AslDictionaryScreen()),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: colors.secondaryContainer.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'These are word-level demonstrations. They do not translate complete sentences using ASL grammar.',
                      style: TextStyle(fontSize: 13, height: 1.4),
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

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.badge,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String badge;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          badge,
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: .7,
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        height: 1.35,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: colors.outline),
            ],
          ),
        ),
      ),
    );
  }
}
