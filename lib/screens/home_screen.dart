import 'package:flutter/material.dart';
import 'main_navigation_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = false;

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
          // Decorative circles removed
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
                        color: const Color(0xFF543310),
                        border: Border.all(color: theme.colorScheme.secondary, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.35),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          )
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/App Logo.png',
                          fit: BoxFit.cover,
                          width: 88,
                          height: 88,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Ready to practice?',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF543310),
                        letterSpacing: 0.8,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Start your next session and level up your musical ear.',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF543310),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 36),
                    SizedBox(
                      width: 220,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF543310),
                          foregroundColor: const Color(0xFFF5F5DD),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _isLoading 
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF5F5DD)),
                                ),
                              )
                            : const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text(
                          _isLoading ? 'Loading...' : 'Start Practice',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        onPressed: _isLoading ? null : () async {
                          try {
                            setState(() {
                              _isLoading = true;
                            });
                            
                            // Add a small delay to show the loading animation
                            await Future.delayed(const Duration(milliseconds: 600));
                            
                            if (mounted) {
                              await Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
                              );
                            }
                          } catch (e) {
                            // Reset loading state if navigation fails
                            if (mounted) {
                              setState(() {
                                _isLoading = false;
                              });
                            }
                          }
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
