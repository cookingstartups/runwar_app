import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Color tokens - Valencia aesthetic (mirrors landing page CSS variables) ──
const Color kBg      = Color(0xFF080E1A);  // Valencia bg
const Color kSurface = Color(0xFF0F1C2E);  // Valencia surface
const Color kBorder  = Color(0x14F5EDD8);  // rgba(245,237,216,0.08)
const Color kAccent  = Color(0xFFFF6B00);  // Valencia accent
const Color kAccent2 = Color(0xFFFFB703);  // Valencia gold / accent2
const Color kFg      = Color(0xFFF5EDD8);  // Valencia fg
const Color kFgMuted = Color(0xFF7A8FA6);  // Valencia mute
const Color kFgFaint = Color(0x40F5EDD8);  // 25% fg
const Color kDanger  = Color(0xFFE83300);  // Valencia danger
const Color kSea = Color(0xFF0096C7);
const Color kLimeGreen = Color(0xFFA6FF00);  // Valencia lime - defender patrol

// Gradient definitions (use with LinearGradient / ShaderMask)
const List<Color> kGradientFire  = [Color(0xFFFF6B00), Color(0xFFE8330A)];
const List<Color> kGradientGold  = [Color(0xFFFFB703), Color(0xFFFF6B00)];
const List<Color> kGradientSea   = [Color(0xFF0096C7), Color(0xFF00B4D8)];

// ── Text styles ─────────────────────────────────────────────────────────────
TextStyle displayStyle({double size = 32, Color color = kFg, double? height}) =>
    GoogleFonts.bebasNeue(
      fontSize: size,
      color: color,
      height: height,
      letterSpacing: 1.5,
    );

TextStyle bodyStyle({double size = 14, Color color = kFgMuted}) =>
    GoogleFonts.spaceGrotesk(
      fontSize: size,
      color: color,
      height: 1.6,
    );

TextStyle monoStyle({double size = 10, Color color = kFgFaint}) =>
    const TextStyle(
      fontFamily: 'monospace',
      fontSize: 10,
      letterSpacing: 2.0,
      color: kFgFaint,
    ).copyWith(fontSize: size, color: color);

TextStyle headlineStyle({double size = 44, Color color = kFg, double? letterSpacing}) =>
    GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: FontWeight.w700,
      color: color,
      letterSpacing: letterSpacing ?? -(size * 0.03),
      height: 0.98,
    );

// ── App ThemeData ────────────────────────────────────────────────────────────
ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBg,
    colorScheme: const ColorScheme.dark(
      surface: kSurface,
      primary: kAccent,
      onPrimary: kBg,
      error: kDanger,
    ),
    textTheme: GoogleFonts.spaceGroteskTextTheme(
      const TextTheme(
        bodyMedium: TextStyle(color: kFgMuted),
        bodyLarge: TextStyle(color: kFg),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kAccent.withValues(alpha: 0.6)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kDanger),
      ),
      hintStyle: const TextStyle(color: kFgFaint, fontSize: 14),
      labelStyle: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 10,
        letterSpacing: 2.0,
        color: kFgFaint,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: kBg,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.spaceGrotesk(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 3.0,
        ),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: kFg,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
