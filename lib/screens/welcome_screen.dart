import 'package:flutter/material.dart';
import 'home_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-0.9, -0.8),
                end: Alignment(1.0, 0.9),
                colors: [
                  Color(0xFFF5F5DD), // beige
                  Color(0xFFF5F5F5), // grey 100
                  Color(0xFFEEEEEE), // grey 200
                  Color(0xFFE0E0E0), // grey 300
                ],
                stops: [0.0, 0.3, 0.7, 1.0],
              ),
            ),
          ),
          Positioned(
            top: -40,
            left: -30,
            child: _DecorCircle(size: 220, color: theme.colorScheme.secondary.withOpacity(0.35)),
          ),
          Positioned(
            bottom: -60,
            right: -20,
            child: _DecorCircle(size: 260, color: theme.colorScheme.primary.withOpacity(0.25)),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                  decoration: BoxDecoration(
                    color: Color(0xFFF5F5DD).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.16),
                        blurRadius: 36,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 104,
                        width: 104,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1976D2), // Solid darker blue
                          border: Border.all(color: theme.colorScheme.secondary.withOpacity(0.8), width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1976D2).withOpacity(0.4),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            )
                          ],
                        ),
                        child: Image.asset(
                          'assets/logo/LOGO.png',
                          width: 52,
                          height: 52,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Welcome to HarmoniSync',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                          letterSpacing: 1.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sharpen your ear, master melodies, and have fun along the way.',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF8B4511).withOpacity(0.65),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.music_note, color: theme.colorScheme.secondary),
                          const SizedBox(width: 12),
                          Icon(Icons.library_music_rounded, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Icon(Icons.audiotrack_rounded, color: theme.colorScheme.secondary),
                        ],
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Color(0xFFF5F5DD),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Let\'s Start'),
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => const HomeScreen()),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DecorCircle extends StatelessWidget {
  final double size;
  final Color color;
  const _DecorCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.35),
            blurRadius: 40,
            spreadRadius: 10,
          ),
        ],
      ),
    );
  }
}
