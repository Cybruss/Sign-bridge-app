import 'package:flutter/material.dart';
import 'home_screen.dart';

void main() {
  runApp(const SignBridgeApp());
}

class SignBridgeApp extends StatelessWidget {
  const SignBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF2A2620);
    final scheme = ColorScheme.light(
      primary: const Color(0xFFAE5736),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFFAF1EB),
      onPrimaryContainer: const Color(0xFF582A1B),
      secondary: const Color(0xFF1A1C22),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFEBE6DD),
      onSecondaryContainer: const Color(0xFF302C26),
      tertiary: const Color(0xFF9A653B),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFF6E8D7),
      onTertiaryContainer: const Color(0xFF4D321E),
      surface: const Color(0xFFFFFDF9),
      onSurface: ink,
      surfaceContainerLow: const Color(0xFFFBF7F0),
      surfaceContainerHighest: const Color(0xFFF0E8DB),
      onSurfaceVariant: const Color(0xFF7A7064),
      outline: const Color(0xFF8A8075),
      outlineVariant: const Color(0xFFE7DFD0),
    );
    return MaterialApp(
      title: 'Sign Bridge',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF6F1E7),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFFF6F1E7),
          foregroundColor: scheme.onSurface,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: const TextStyle(
            color: ink,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          color: scheme.surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.primary, width: 1.5),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFFEBE6DD),
          indicatorColor: scheme.primaryContainer,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            );
          }),
        ),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
