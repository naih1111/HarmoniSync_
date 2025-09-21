import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/music_service.dart';
import 'exercise_screen.dart';

class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B4511), // Top bar background (Saddle Brown). Change this to alter the AppBar background.
        foregroundColor: Color(0xFFF5F5DD), // Top bar text/icons color. Change this for AppBar title and icons.
        title: const Text('Practice Session'),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.9, -0.8),
            end: Alignment(1.0, 0.9),
            colors: [
              Color(0xFFF5F5DD),
        Color(0xFFF5F5DD),
        Color(0xFFF5F5DD),
        Color(0xFFF5F5DD),
            ],
            stops: [0.0, 0.35, 0.7, 1.0],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              // Easy Section
              const SectionHeader(title: 'Easy'),
              
              // Horizontal scrollable Level 1 exercises
              SizedBox(
                height: 150, // Fixed height for square cards
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 5, // Number of Level 1 exercises
                  itemBuilder: (context, index) {
                    return Container(
                      width: 150, // Square width
                      margin: const EdgeInsets.only(right: 12.0),
                      child: Card(
                        color: const Color(0xFFC7AD7F),
                        child: InkWell(
                          onTap: () => _navigateToExercise(context, '1'),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SvgPicture.asset(
                                  'assets/sheet${index + 1}.svg',
                                  width: 60,
                                  height: 60,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Exercise ${index + 1}',
                                  style: const TextStyle(
                                    color: Color(0xFFF5F5DD),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Level 1',
                                  style: TextStyle(
                                    color: Color(0xFFF5F5DD).withOpacity(0.7),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Medium Section
              const SectionHeader(title: 'Medium'),
              
              // Horizontal scrollable Level 2 exercises
              SizedBox(
                height: 150, // Fixed height for square cards
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 5, // Number of Level 2 exercises
                  itemBuilder: (context, index) {
                    return Container(
                      width: 150, // Square width
                      margin: const EdgeInsets.only(right: 12.0),
                      child: Card(
                        color: const Color(0xFFCC9767),
                        child: InkWell(
                          onTap: () => _navigateToExercise(context, '2'),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SvgPicture.asset(
                                  'assets/sheet${index + 1}.svg',
                                  width: 60,
                                  height: 60,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Exercise ${index + 1}',
                                  style: const TextStyle(
                                    color: Color(0xFFF5F5DD),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Level 2',
                                  style: TextStyle(
                                    color: Color(0xFFF5F5DD).withOpacity(0.7),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Hard Section
              const SectionHeader(title: 'Hard'),
              
              // Horizontal scrollable Level 3 exercises
              SizedBox(
                height: 150, // Fixed height for square cards
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 5, // Number of Level 3 exercises
                  itemBuilder: (context, index) {
                    return Container(
                      width: 150, // Square width
                      margin: const EdgeInsets.only(right: 12.0),
                      child: Card(
                        color: const Color(0xFFA57A5A),
                        child: InkWell(
                          onTap: () => _navigateToExercise(context, '3'),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SvgPicture.asset(
                                  'assets/sheet${index + 1}.svg',
                                  width: 60,
                                  height: 60,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Exercise ${index + 1}',
                                  style: const TextStyle(
                                    color: Color(0xFFF5F5DD),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Level 3',
                                  style: TextStyle(
                                    color: Color(0xFFF5F5DD).withOpacity(0.7),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToExercise(BuildContext context, String level) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExerciseScreen(level: level),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Text(
        title,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// A simple, tappable card used as a "button" for practice levels.
///
/// Customize colors by passing:
/// - backgroundColor: card's background
/// - titleColor: title text color
/// - iconColor: trailing arrow icon color
class ExerciseCard extends StatelessWidget {
  final String title;
  final String level;
  final VoidCallback onTap;
  // Optional colors to customize this "button"
  final Color? backgroundColor; // Card background color (pass a Color to override)
  final Color? titleColor;      // Title text color (pass a Color to override)
  final Color? iconColor;       // Trailing arrow icon color (pass a Color to override)

  const ExerciseCard({
    super.key, 
    required this.title,
    required this.level,
    required this.onTap,
    this.backgroundColor, // Set to change card background
    this.titleColor,      // Set to change text color
    this.iconColor,       // Set to change trailing icon color
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: backgroundColor, // Background color for the card
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: titleColor, // Title text color
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 18,
          color: iconColor ?? theme.colorScheme.primary, // Trailing icon color (defaults to theme primary if null)
        ),
        onTap: onTap,
      ),
    );
  }
}

