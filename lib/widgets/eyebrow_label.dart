import 'package:flutter/material.dart';
import '../theme.dart';

class EyebrowLabel extends StatelessWidget {
  const EyebrowLabel(this.text, {super.key, this.color = kAccent});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 10,
        letterSpacing: 3.0,
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
