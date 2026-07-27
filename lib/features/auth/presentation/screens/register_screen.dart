import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../widgets/auth_page_scaffold.dart';
import '../../domain/services/password_policy.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.onSignUp,
    required this.onAuthenticated,
  });

  final Future<void> Function(String name, String email, String password)
  onSignUp;
  final VoidCallback onAuthenticated;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _isLoading = false;
  bool _acceptedTerms = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      title: 'Join your community.',
      subtitle: 'Create your TurkSquare account and meet Turks across America.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthInput(
            controller: _name,
            label: 'Full name',
            hint: 'Ahmet Yılmaz',
            icon: Icons.person_outline_rounded,
            keyboardType: TextInputType.name,
          ),
          const SizedBox(height: 15),
          AuthInput(
            controller: _email,
            label: 'Email',
            hint: 'example@email.com',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 15),
          AuthInput(
            controller: _password,
            label: 'Password',
            hint: 'At least 6 characters',
            icon: Icons.lock_outline_rounded,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          const SizedBox(height: 15),
          AuthInput(
            controller: _confirmPassword,
            label: 'Confirm password',
            hint: 'Repeat your password',
            icon: Icons.verified_user_outlined,
            obscureText: _obscurePassword,
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            value: _acceptedTerms,
            onChanged: (value) =>
                setState(() => _acceptedTerms = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.primary,
            title: const Text(
              'I agree to the Terms and Privacy Policy.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          AuthPrimaryButton(
            label: 'Create Account',
            onPressed: _createAccount,
            isLoading: _isLoading,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Already have an account? Sign In'),
          ),
        ],
      ),
    );
  }

  Future<void> _createAccount() async {
    if (!_acceptedTerms)
      return _show('Please accept the Terms and Privacy Policy.');
    if (_password.text != _confirmPassword.text)
      return _show('Passwords do not match.');
    if (PasswordPolicy.validate(
          _password.text,
          email: _email.text,
          name: _name.text,
        )
        case final error?)
      return _show(error);
    setState(() => _isLoading = true);
    try {
      await widget.onSignUp(_name.text, _email.text, _password.text);
      if (mounted) widget.onAuthenticated();
    } catch (_) {
      if (mounted) _show('Please review your details and try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _show(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}
