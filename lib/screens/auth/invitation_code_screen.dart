import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../theme.dart';

class InvitationCodeScreen extends ConsumerStatefulWidget {
  const InvitationCodeScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<InvitationCodeScreen> createState() =>
      _InvitationCodeScreenState();
}

class _InvitationCodeScreenState extends ConsumerState<InvitationCodeScreen> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    final success = await ref
        .read(authProvider.notifier)
        .redeemCode(code, widget.userId);
    if (success && mounted) {
      // The root route guard watches authProvider — once invited_at is set it
      // will rebuild to the next destination automatically. Pop this screen so
      // we don't leave it on the stack.
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authProvider);
    final loading = state.isLoading;
    final errorText = state.error;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Text('ENTER INVITATION CODE', style: displayStyle(size: 32)),
              const SizedBox(height: 8),
              Text(
                'This is an invitation-only game.',
                style: bodyStyle(size: 14, color: kFgMuted),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _codeController,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => loading ? null : _submit(),
                onChanged: (_) => ref.read(authProvider.notifier).clearError(),
                inputFormatters: [
                  // Allow only letters, digits, and hyphens; max 20 chars.
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
                  LengthLimitingTextInputFormatter(20),
                  _UpperCaseTextFormatter(),
                ],
                decoration: const InputDecoration(
                  labelText: 'INVITATION CODE',
                  hintText: 'FOUNDING-VLCR-001',
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorText,
                  style: bodyStyle(size: 13, color: kDanger),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: loading ? null : _submit,
                child: loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kBg,
                        ),
                      )
                    : const Text('ACTIVATE'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Forces all input to uppercase automatically.
class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
