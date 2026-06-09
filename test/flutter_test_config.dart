// test/flutter_test_config.dart
//
// Global test configuration for all Flutter widget tests in this project.
//
// Disables the MaterialApp debug banner (BannerPainter CustomPaint) so that
// widget tests using find.byType(CustomPaint) can find exactly the custom
// painter widgets they expect, without interference from the debug banner.

import 'dart:async';
import 'package:flutter/material.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Suppress the debug-mode "DEBUG" banner that MaterialApp renders via
  // WidgetsApp -> CheckedModeBanner -> CustomPaint(foregroundPainter: BannerPainter).
  // Without this, any find.byType(CustomPaint) call finds 2 widgets instead of 1.
  WidgetsApp.debugAllowBannerOverride = false;
  await testMain();
}
