/// Capitalises the first character of [s], leaving the rest unchanged.
/// Returns the input unchanged when empty or already capitalised.
/// Non-ASCII safe — uses Dart's String.toUpperCase on the first code unit.
String capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}
