import 'package:flutter/material.dart';
import 'home_screen.dart';

void main() {
  runApp(const SignBridgeApp());
}

class SignBridgeApp extends StatelessWidget {
  const SignBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sign Bridge',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}