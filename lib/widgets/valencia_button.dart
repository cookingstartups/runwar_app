import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

enum ValenciaButtonVariant { primary, ghost, accentOutline }

class ValenciaButton extends StatelessWidget {
  const ValenciaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ValenciaButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final ValenciaButtonVariant variant;
  final Widget? icon;
  final bool loading;
  final bool enabled;

  static const _kHeight = 52.0;

  @override
  Widget build(BuildContext context) {
    final labelStyle = GoogleFonts.spaceGrotesk(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 3.0,
    );

    final effective = enabled && !loading ? onPressed : null;

    switch (variant) {
      case ValenciaButtonVariant.primary:
        return _GradientButton(
          label: label,
          icon: icon,
          loading: loading,
          onPressed: effective,
          labelStyle: labelStyle,
        );
      case ValenciaButtonVariant.ghost:
        return SizedBox(
          width: double.infinity,
          height: _kHeight,
          child: OutlinedButton.icon(
            onPressed: effective,
            icon: icon ?? const SizedBox.shrink(),
            label: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kFg))
                : Text(label, style: labelStyle.copyWith(color: kFg)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kBorder),
              shape: const StadiumBorder(),
              foregroundColor: kFg,
            ),
          ),
        );
      case ValenciaButtonVariant.accentOutline:
        return SizedBox(
          width: double.infinity,
          height: _kHeight,
          child: OutlinedButton.icon(
            onPressed: effective,
            icon: icon ?? const SizedBox.shrink(),
            label: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent))
                : Text(label, style: labelStyle.copyWith(color: kAccent)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kAccent),
              shape: const StadiumBorder(),
              foregroundColor: kAccent,
            ),
          ),
        );
    }
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.onPressed,
    required this.labelStyle,
    this.icon,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final TextStyle labelStyle;
  final Widget? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(100),
          child: Ink(
            decoration: BoxDecoration(
              gradient: onPressed != null
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: kGradientFire,
                    )
                  : null,
              color: onPressed == null ? kBorder : null,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Center(
              child: loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kBg))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[icon!, const SizedBox(width: 8)],
                        Text(label, style: labelStyle.copyWith(color: kBg)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
