import 'package:flutter/material.dart';
import 'main_navigation_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-0.9, -1.0),
                end: Alignment(1.0, 0.9),
                colors: [
                  Color(0xFFF5F5DD), // beige
                  Color(0xFFF3F3D1), // lighter beige
                  Color(0xFFF1F1CF), // even lighter beige
                  Color(0xFFEFEFCD), // lightest beige
                ],
                stops: [0.0, 0.35, 0.7, 1.0],
              ),
            ),
          ),
          Positioned(
            top: -50,
            right: -30,
            child: _DecorCircle(size: 200, color: theme.colorScheme.secondary.withOpacity(0.30)),
          ),
          Positioned(
            bottom: -60,
            left: -20,
            child: _DecorCircle(size: 260, color: theme.colorScheme.primary.withOpacity(0.22)),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      height: 88,
                      width: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primary,
                        border: Border.all(color: theme.colorScheme.secondary, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.35),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          )
                        ],
                      ),
                      child: const Icon(Icons.queue_music_rounded, color: Color(0xFFF5F5DD), size: 40),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Ready to practice?',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                        letterSpacing: 0.8,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Start your next session and level up your musical ear.',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.black.withOpacity(0.65),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 36),
                    SizedBox(
                      width: 220,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Color(0xFFF5F5DD),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Start Practice'),
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
                          );
                        },
                      ),
                    ),
                  ],
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
            color: color.withOpacity(0.4),
            blurRadius: 36,
            spreadRadius: 8,
          ),
        ],
      ),
    );
  }
}
