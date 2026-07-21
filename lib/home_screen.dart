import 'package:flutter/material.dart';
import 'sign_to_text_screen.dart';
import 'screens/avatar_pipeline_screen.dart';
// in HomeScreen._buildFeatureButton add a button pointing to SignTestScreen()
import 'screens/sign_test_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Screen'),
        backgroundColor: Colors.blue[700],
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue[700]!, const Color.fromARGB(255, 201, 201, 201)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Logo/Icon
              const Icon(
                Icons.accessible_forward,
                size: 100,
                color: Colors.white,
              ),
              const SizedBox(height: 30),
              
              // App Title
              const Text(
                'Sign Bridge',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Bridging Communication Gap',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 50),
              
              // Feature Buttons
              _buildFeatureButton(
                context,
                'Text to Sign',
                Icons.text_fields,
                Colors.green,
                AvatarPipelineScreen(),
              ),
              const SizedBox(height: 20),
              _buildFeatureButton(
                context,
                'Sign to Text',
                Icons.camera_alt,
                Colors.orange,
                SignToTextScreen(),
              ),
              const SizedBox(height: 20),
              _buildFeatureButton(
                context,
                'Sign Test',
                Icons.check_circle,
                Colors.blue,
                SignTestScreen(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureButton(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    Widget screen,
  ) {
    return SizedBox(
      width: 250,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => screen),
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}