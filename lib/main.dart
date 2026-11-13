import 'package:flutter/material.dart';
import 'home_screen.dart';

void main() {
  runApp(const SignBridgeApp());
}

class SignBridgeApp extends StatelessWidget {
  const SignBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF182D36);
    final scheme = ColorScheme.light(
      primary: const Color(0xFF0B6B67),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFD6ECE9),
      onPrimaryContainer: const Color(0xFF083F3D),
      secondary: const Color(0xFF315C7A),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFDCE8F0),
      onSecondaryContainer: const Color(0xFF18384F),
      tertiary: const Color(0xFFA75E3B),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFF4E1D7),
      onTertiaryContainer: const Color(0xFF542716),
      surface: Colors.white,
      onSurface: ink,
      surfaceContainerLow: const Color(0xFFF7F9FA),
      surfaceContainerHighest: const Color(0xFFEAF0F2),
      onSurfaceVariant: const Color(0xFF52656D),
      outline: const Color(0xFF71838A),
      outlineVariant: const Color(0xFFD5DFE2),
    );
    return MaterialApp(
      title: 'Sign Bridge',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF2F6F7),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFFF2F6F7),
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
          backgroundColor: const Color(0xFFEAF0F2),
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
