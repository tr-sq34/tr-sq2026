import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../widgets/auth_page_scaffold.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.onRequestReset});
  final Future<void> Function(String email) onRequestReset;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _isLoading = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      title: _sent ? 'Check your inbox.' : 'Reset your password.',
      subtitle: _sent
          ? 'We sent a reset link to ${_email.text}.'
          : 'Enter the email linked to your TurkSquare account.',
      child: _sent ? _confirmation() : _form(),
    );
  }

  Widget _form() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AuthInput(
        controller: _email,
        label: 'Email',
        hint: 'example@email.com',
        icon: Icons.mail_outline_rounded,
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: 22),
      AuthPrimaryButton(
        label: 'Send Reset Link',
        onPressed: _send,
        isLoading: _isLoading,
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Back to Sign In'),
      ),
    ],
  );

  Widget _confirmation() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(
        Icons.mark_email_read_outlined,
        color: AppColors.accentEmerald,
        size: 54,
      ),
      const SizedBox(height: 16),
      const Text(
        'Demo mode: no email is sent yet. The backend will plug into this same flow.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          height: 1.45,
        ),
      ),
      const SizedBox(height: 22),
      AuthPrimaryButton(
        label: 'Back to Sign In',
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );

  Future<void> _send() async {
    setState(() => _isLoading = true);
    try {
      await widget.onRequestReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid email address.')),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
