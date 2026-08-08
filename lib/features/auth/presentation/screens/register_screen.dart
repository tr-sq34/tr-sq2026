import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../widgets/auth_page_scaffold.dart';
import '../../domain/services/password_policy.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.onSignUp,
    required this.onAuthenticated,
    this.initialEmail,
    this.onVerificationRequired,
  });

  final Future<void> Function(String name, String email, String password)
  onSignUp;
  final VoidCallback onAuthenticated;
  final String? initialEmail;
  final Future<void> Function(String email)? onVerificationRequired;

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
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _email.text = widget.initialEmail?.trim() ?? '';
  }

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
          const Row(
            children: [
              Icon(
                Icons.person_add_alt_1_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              SizedBox(width: 8),
              Text(
                'Step 1 of 2  •  Account details',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
            enableInteractiveSelection: false,
            onChanged: (_) => setState(() {}),
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
          const SizedBox(height: 8),
          _PasswordChecklist(
            password: _password.text,
            email: _email.text,
            name: _name.text,
          ),
          const SizedBox(height: 15),
          AuthInput(
            controller: _confirmPassword,
            label: 'Confirm password',
            hint: 'Repeat your password',
            icon: Icons.verified_user_outlined,
            obscureText: _obscureConfirmPassword,
            enableInteractiveSelection: false,
            suffixIcon: IconButton(
              tooltip: _obscureConfirmPassword
                  ? 'Show password'
                  : 'Hide password',
              onPressed: () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              ),
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
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
    if (!_acceptedTerms) {
      return _show('Please accept the Terms and Privacy Policy.');
    }
    if (_password.text != _confirmPassword.text) {
      return _show('Passwords do not match.');
    }
    if (PasswordPolicy.validate(
          _password.text,
          email: _email.text,
          name: _name.text,
        )
        case final error?) {
      return _show(error);
    }
    setState(() => _isLoading = true);
    try {
      await widget.onSignUp(_name.text, _email.text, _password.text);
      if (mounted) {
        final email = _email.text.trim();
        final onVerificationRequired = widget.onVerificationRequired;
        if (onVerificationRequired != null) {
          await onVerificationRequired(email);
        } else {
          _show('Doğrulama kodu e-posta adresinize gönderildi.');
        }
      }
    } catch (error) {
      if (mounted) _show(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _show(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _PasswordChecklist extends StatelessWidget {
  const _PasswordChecklist({
    required this.password,
    required this.email,
    required this.name,
  });
  final String password;
  final String email;
  final String name;

  @override
  Widget build(BuildContext context) {
    final validLength = password.trim().length >= PasswordPolicy.minLength;
    final validIdentity =
        PasswordPolicy.validate(password, email: email, name: name) == null ||
        !validLength;
    Widget item(bool ok, String text) => Row(
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 15,
          color: ok ? Colors.green : AppColors.textMuted,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Password security',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 6),
          item(validLength, 'At least 12 characters'),
          const SizedBox(height: 4),
          item(validIdentity, 'Does not include your name or email'),
        ],
      ),
    );
  }
}
