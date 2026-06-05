import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../theme.dart';

// Static counter to track how many claims this session (for free-text trigger)
int _claimCountThisSession = 0;

Future<void> showFeedbackEmojiSheet(
  BuildContext context, {
  required String trigger,
}) async {
  if (trigger == 'claim_made') _claimCountThisSession++;
  final showFreeText = _claimCountThisSession >= 3;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: kSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _FeedbackSheet(
      trigger: trigger,
      showFreeText: showFreeText,
    ),
  );
}

class _FeedbackSheet extends StatefulWidget {
  final String trigger;
  final bool showFreeText;
  const _FeedbackSheet({required this.trigger, required this.showFreeText});

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  Future<void> _save(String rating) async {
    setState(() => _saving = true);
    final now = DateTime.now().toUtc().toIso8601String();
    await DatabaseService.instance.insertFeedback(
      '${DateTime.now().microsecondsSinceEpoch}',
      null, // userId not available in widget context
      widget.trigger,
      rating,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      createdAt: now,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('How was that?',
            style: TextStyle(color: kFg, fontSize: 18, fontFamily: 'BebasNeue')),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['😍', '🙂', '😐', '😞'].map((e) =>
              GestureDetector(
                onTap: _saving ? null : () => _save(e),
                child: Text(e, style: const TextStyle(fontSize: 36)),
              )
            ).toList(),
          ),
          if (widget.showFreeText) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _noteCtrl,
              style: TextStyle(color: kFg),
              decoration: InputDecoration(
                hintText: 'Tell us more (optional)',
                hintStyle: TextStyle(color: kFgMuted),
                filled: true,
                fillColor: kBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: kBorder),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
