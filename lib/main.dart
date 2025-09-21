import 'package:flutter/material.dart';
//import 'screens/pitch_detector_screen.dart';
import 'screens/welcome_screen.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  //runApp(const MaterialApp(home: PitchDetectorScreen()));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

 @override
 Widget build(BuildContext context) {
   final baseLight = ThemeData(
     useMaterial3: true,
     colorSchemeSeed: Colors.grey[900],
     brightness: Brightness.light,
   );
   final baseDark = ThemeData(
     useMaterial3: true,
     colorSchemeSeed: Colors.grey[900],
     brightness: Brightness.dark,
   );

   // Black + White palette
   const primaryBlack = Color(0xFF8B4511); // Saddle Brown
   const secondaryGrey = Color(0xFF424242); // dark grey
   const tertiaryBlack = Color(0xFF212121); // very dark grey

   ColorScheme lightScheme = baseLight.colorScheme.copyWith(
     primary: primaryBlack,
     secondary: secondaryGrey,
     tertiary: tertiaryBlack,
     surface: Colors.white,
     background: Colors.white,
   );
   ColorScheme darkScheme = baseDark.colorScheme.copyWith(
     primary: tertiaryBlack,
     secondary: const Color(0xFF616161),
     tertiary: const Color(0xFF424242),
   );

   final textThemeLight = TextTheme(
     displayLarge: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     displayMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     displaySmall: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     headlineLarge: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     headlineMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     headlineSmall: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     titleLarge: GoogleFonts.poppins(fontWeight: FontWeight.w700),
     titleMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     titleSmall: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     bodyLarge: GoogleFonts.poppins(),
     bodyMedium: GoogleFonts.poppins(),
     bodySmall: GoogleFonts.poppins(),
     labelLarge: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     labelMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     labelSmall: GoogleFonts.poppins(fontWeight: FontWeight.w600),
   );

   final textThemeDark = TextTheme(
     displayLarge: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     displayMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     displaySmall: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     headlineLarge: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     headlineMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     headlineSmall: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     titleLarge: GoogleFonts.poppins(fontWeight: FontWeight.w700),
     titleMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     titleSmall: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     bodyLarge: GoogleFonts.poppins(),
     bodyMedium: GoogleFonts.poppins(),
     bodySmall: GoogleFonts.poppins(),
     labelLarge: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     labelMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600),
     labelSmall: GoogleFonts.poppins(fontWeight: FontWeight.w600),
   );

   return MaterialApp(
     title: 'HarmoniSync Solfege Trainer',
     debugShowCheckedModeBanner: false,
     themeMode: ThemeMode.system,
     theme: baseLight.copyWith(
       colorScheme: lightScheme,
       appBarTheme: AppBarTheme(
         centerTitle: true,
         backgroundColor: Colors.white.withOpacity(0.90),
         elevation: 0,
         surfaceTintColor: Colors.transparent,
         foregroundColor: lightScheme.primary,
       ),
       textTheme: textThemeLight,
       elevatedButtonTheme: ElevatedButtonThemeData(
         style: ElevatedButton.styleFrom(
           backgroundColor: lightScheme.primary,
           foregroundColor: Colors.white,
           padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
           shape: RoundedRectangleBorder(
             borderRadius: BorderRadius.circular(12),
           ),
           textStyle: const TextStyle(fontWeight: FontWeight.w700),
         ),
       ),
       textButtonTheme: TextButtonThemeData(
         style: TextButton.styleFrom(
           foregroundColor: lightScheme.primary,
           textStyle: const TextStyle(fontWeight: FontWeight.w700),
         ),
       ),
       outlinedButtonTheme: OutlinedButtonThemeData(
         style: OutlinedButton.styleFrom(
           foregroundColor: lightScheme.primary,
           side: BorderSide(color: lightScheme.primary),
           textStyle: const TextStyle(fontWeight: FontWeight.w700),
         ),
       ),
       iconButtonTheme: IconButtonThemeData(
         style: IconButton.styleFrom(
           foregroundColor: lightScheme.primary,
         ),
       ),
       cardTheme: CardThemeData(
         elevation: 1,
         shape: RoundedRectangleBorder(
           borderRadius: BorderRadius.circular(16),
         ),
         surfaceTintColor: lightScheme.surfaceTint,
       ),
             navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: lightScheme.secondary.withValues(alpha: 0.20),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: lightScheme.primary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(color: lightScheme.primary);
        }),
      ),
     ),
     darkTheme: baseDark.copyWith(
       colorScheme: darkScheme,
       appBarTheme: AppBarTheme(
         centerTitle: true,
         backgroundColor: Color(0xFF8B4511).withOpacity(0.10),
         elevation: 0,
         surfaceTintColor: Colors.transparent,
         foregroundColor: Colors.white,
       ),
       textTheme: textThemeDark,
       elevatedButtonTheme: ElevatedButtonThemeData(
         style: ElevatedButton.styleFrom(
           backgroundColor: darkScheme.primary,
           foregroundColor: Colors.white,
           padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
           shape: RoundedRectangleBorder(
             borderRadius: BorderRadius.circular(12),
           ),
           textStyle: const TextStyle(fontWeight: FontWeight.w700),
         ),
       ),
       textButtonTheme: TextButtonThemeData(
         style: TextButton.styleFrom(
           foregroundColor: darkScheme.primary,
           textStyle: const TextStyle(fontWeight: FontWeight.w700),
         ),
       ),
       outlinedButtonTheme: OutlinedButtonThemeData(
         style: OutlinedButton.styleFrom(
           foregroundColor: darkScheme.primary,
           side: BorderSide(color: darkScheme.primary),
           textStyle: const TextStyle(fontWeight: FontWeight.w700),
         ),
       ),
       iconButtonTheme: IconButtonThemeData(
         style: IconButton.styleFrom(
           foregroundColor: darkScheme.primary,
         ),
       ),
       cardTheme: CardThemeData(
         elevation: 1,
         shape: RoundedRectangleBorder(
           borderRadius: BorderRadius.circular(16),
         ),
         surfaceTintColor: darkScheme.surfaceTint,
       ),
             navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkScheme.surface,
        indicatorColor: darkScheme.secondary.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: darkScheme.primary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(color: darkScheme.primary);
        }),
      ),
     ),
     home: const WelcomeScreen(), // Start here
   );
 }
}