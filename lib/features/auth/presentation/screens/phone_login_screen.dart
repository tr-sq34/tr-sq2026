import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/auth_page_scaffold.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({
    super.key,
    required this.onRequestCode,
    required this.onVerifyCode,
    required this.onAuthenticated,
  });

  final Future<void> Function(String phoneNumber) onRequestCode;
  final Future<void> Function(String phoneNumber, String code) onVerifyCode;
  final VoidCallback onAuthenticated;

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      title: _codeSent ? 'Confirm your number.' : 'Continue with phone.',
      subtitle: _codeSent
          ? 'Enter the 6-digit verification code sent to ${_phone.text}.'
          : 'We will send a one-time code to verify your phone number.',
      child: _codeSent ? _codeForm() : _phoneForm(),
    );
  }

  Widget _phoneForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AuthInput(
        controller: _phone,
        label: 'Phone number',
        hint: '+1 (555) 000-0000',
        icon: Icons.phone_iphone_rounded,
        keyboardType: TextInputType.phone,
      ),
      const SizedBox(height: 10),
      const Text(
        'We use your number only for verification and account security.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
      ),
      const SizedBox(height: 22),
      AuthPrimaryButton(
        label: 'Send Verification Code',
        onPressed: _requestCode,
        isLoading: _isLoading,
      ),
    ],
  );

  Widget _codeForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AuthInput(
        controller: _code,
        label: 'Verification code',
        hint: '123456',
        icon: Icons.password_rounded,
        keyboardType: TextInputType.number,
        maxLength: 6,
      ),
      const SizedBox(height: 10),
      const DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0x1A3B82F6),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Demo code: 123456',
            style: TextStyle(
              color: AppColors.primaryLight,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      const SizedBox(height: 22),
      AuthPrimaryButton(
        label: 'Verify and Continue',
        onPressed: _verifyCode,
        isLoading: _isLoading,
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: _isLoading ? null : () => setState(() => _codeSent = false),
        child: const Text('Change phone number'),
      ),
    ],
  );

  Future<void> _requestCode() async {
    setState(() => _isLoading = true);
    try {
      await widget.onRequestCode(_phone.text);
      if (mounted) setState(() => _codeSent = true);
    } catch (_) {
      if (mounted) _show('Enter a valid phone number.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    setState(() => _isLoading = true);
    try {
      await widget.onVerifyCode(_phone.text, _code.text);
      if (mounted) widget.onAuthenticated();
    } catch (_) {
      if (mounted) _show('That verification code is not correct.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _show(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}
