import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Color tokens (mirrors the landing page CSS variables) ──────────────────
const Color kBg = Color(0xFF08060F);
const Color kSurface = Color(0xFF12111A);
const Color kBorder = Color(0xFF1E1C28);
const Color kAccent = Color(0xFFFF7A00); // rw-accent — orange
const Color kFg = Color(0xFFFFFFFF);
const Color kFgMuted = Color(0x99FFFFFF); // 60% white
const Color kFgFaint = Color(0x40FFFFFF); // 25% white
const Color kDanger = Color(0xFFFF3B30);

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
      labelStyle: TextStyle(
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
