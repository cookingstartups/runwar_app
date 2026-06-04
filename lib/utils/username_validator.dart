// Returns null if valid, user-facing error string if not.
String? validateUsername(String input) {
  final t = input.trim();
  if (t != input) return "Usernames can't contain spaces.";
  if (t.contains(RegExp(r'\s'))) return "Usernames can't contain spaces.";
  if (t.length < 3 || t.length > 20) return '3–20 characters required.';
  if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(t)) return 'Letters, digits, and underscore only.';
  final lower = t.toLowerCase();
  if (RegExp(r'_bot').hasMatch(lower)) return 'This name pattern is reserved. Pick another.';
  if (RegExp(r'\.bot').hasMatch(lower)) return 'This name pattern is reserved. Pick another.';
  if (RegExp(r'^bot[._]').hasMatch(lower)) return 'This name pattern is reserved. Pick another.';
  if (RegExp(r'bot$').hasMatch(lower)) return 'This name pattern is reserved. Pick another.';
  return null;
}
