import 'package:flutter/material.dart';

import 'screens/sign_test_screen.dart';
import 'screens/text_to_sign_hub_screen.dart';
import 'sign_to_text_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  void _selectTab(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: _selectedIndex == 0
          ? AppBar(
              titleSpacing: 20,
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.sign_language,
                      color: colors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Text(
                    'Sign Bridge',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Model check',
                  onPressed: () => _open(context, const SignTestScreen()),
                  icon: const Icon(Icons.info_outline_rounded),
                ),
                const SizedBox(width: 8),
              ],
            )
          : null,
      body: _selectedIndex == 1
          ? SignToTextScreen()
          : _selectedIndex == 2
          ? const TextToSignHubScreen()
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 22, 20, 22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [colors.primary, const Color(0xFF173B54)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: .16),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Text(
                            'SIGN LANGUAGE • PROJECT DEMO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Communication,\nmade more accessible.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 27,
                            height: 1.14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Explore sign recognition and visual sign demos.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .78),
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 19),
                        FilledButton.icon(
                          onPressed: () => _selectTab(1),
                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                          label: const Text('Start sign recognition'),
                          style: FilledButton.styleFrom(
                            foregroundColor: colors.primary,
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  const _SectionTitle(
                    title: 'Explore the prototype',
                    subtitle: 'Choose a direction to get started',
                  ),
                  const SizedBox(height: 13),
                  _FeatureCard(
                    icon: Icons.videocam_outlined,
                    title: 'Sign to text',
                    subtitle: 'Use the camera to recognize isolated words',
                    tag: 'ON DEVICE',
                    color: const Color(0xFF147D78),
                    onTap: () => _selectTab(1),
                  ),
                  const SizedBox(height: 10),
                  _FeatureCard(
                    icon: Icons.sign_language_rounded,
                    title: 'Text to sign',
                    subtitle:
                        'Local avatar examples, SiGML, and online fallback',
                    tag: '3 OPTIONS',
                    color: const Color(0xFF4962A8),
                    onTap: () => _selectTab(2),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: .65),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          color: colors.primary,
                          size: 21,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            'Demo note: recognition covers isolated words. The avatar and online options are limited demonstrations, not full sentence translation.',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _open(context, const SignTestScreen()),
                      icon: const Icon(Icons.fact_check_outlined, size: 17),
                      label: const Text('Model diagnostics'),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            selectedIcon: Icon(Icons.videocam_rounded),
            label: 'Sign to Text',
          ),
          NavigationDestination(
            icon: Icon(Icons.sign_language_outlined),
            selectedIcon: Icon(Icons.sign_language_rounded),
            label: 'Text to Sign',
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String tag;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .7),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 23),
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
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tag,
                          style: TextStyle(
                            color: color,
                            fontSize: 9,
                            letterSpacing: .55,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
