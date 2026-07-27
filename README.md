# runwar_app

A new Flutter project.

## Build and run

Install dependencies:

```bash
flutter pub get
```

Run on a connected device or emulator:

```bash
flutter run
```

Build a debug APK:

```bash
flutter build apk --debug
```

The APK lands at `build/app/outputs/flutter-apk/app-debug.apk`. Install it on a
connected device with:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Run static analysis and the test suite together:

```bash
scripts/check.sh
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
