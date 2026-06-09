import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityProvider = StreamProvider<bool>((ref) async* {
  try {
    final initial = await Connectivity().checkConnectivity();
    yield initial.any((r) => r != ConnectivityResult.none);
  } catch (e) {
    debugPrint('[Connectivity] checkConnectivity failed: $e');
    yield false;
  }
  yield* Connectivity()
      .onConnectivityChanged
      .map((results) => results.any((r) => r != ConnectivityResult.none));
});
