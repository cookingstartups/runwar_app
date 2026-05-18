import 'dart:async';
import 'package:flutter/material.dart';

import '../services/waitlist_service.dart';
import '../theme.dart';

class CityAutocompleteField extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<String> onChanged;
  final FormFieldValidator<String>? validator;

  const CityAutocompleteField({
    super.key,
    this.initialValue,
    required this.onChanged,
    this.validator,
  });

  @override
  State<CityAutocompleteField> createState() => _CityAutocompleteFieldState();
}

class _CityAutocompleteFieldState extends State<CityAutocompleteField> {
  final _controller = TextEditingController();
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  Timer? _debounce;

  List<String> _suggestions = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _showOverlay(BuildContext context) {
    _removeOverlay();
    if (_suggestions.isEmpty) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;

    _overlay = OverlayEntry(
      builder: (_) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          offset: Offset(0, size.height + 4),
          child: Material(
            color: kSurface,
            borderRadius: BorderRadius.circular(10),
            elevation: 8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _suggestions
                  .map(
                    (s) => InkWell(
                      onTap: () {
                        _controller.text = s;
                        widget.onChanged(s);
                        _removeOverlay();
                        setState(() => _suggestions = []);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: kBorder, width: 0.5),
                          ),
                        ),
                        child: Text(s, style: bodyStyle(size: 13, color: kFgMuted)),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlay!);
  }

  void _onChanged(String value) {
    widget.onChanged(value);
    _debounce?.cancel();

    if (value.length < 2) {
      _removeOverlay();
      setState(() => _suggestions = []);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _loading = true);
      final results = await WaitlistService.searchCities(value);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _loading = false;
      });
      _showOverlay(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: _controller,
        onChanged: _onChanged,
        autocorrect: false,
        style: bodyStyle(size: 14, color: kFg),
        decoration: InputDecoration(
          hintText: 'Start typing your city…',
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('CITY', style: monoStyle(size: 10, color: kFgFaint)),
              if (_loading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: kAccent,
                  ),
                ),
              ],
            ],
          ),
        ),
        validator: widget.validator,
      ),
    );
  }
}
