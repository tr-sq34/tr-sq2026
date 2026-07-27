import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.onSignIn,
    this.onAuthenticated,
    this.onForgotPassword,
    this.onCreateAccount,
    this.onPhoneLogin,
    this.onPasskeyLogin,
  });

  final Future<void> Function(String email, String password)? onSignIn;
  final VoidCallback? onAuthenticated;
  final VoidCallback? onForgotPassword;
  final VoidCallback? onCreateAccount;
  final VoidCallback? onPhoneLogin;
  final Future<void> Function({String? email})? onPasskeyLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _SoftGradientBackground(),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: Column(
                    children: [
                      const _BrandHeader(),
                      const SizedBox(height: 24),
                      _buildLoginCard(),
                      const SizedBox(height: 20),
                      const _TrustIndicators(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InputField(
                controller: _emailController,
                label: 'Email',
                hint: 'example@email.com',
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.mail_outline_rounded,
              ),
              const SizedBox(height: 16),
              _InputField(
                controller: _passwordController,
                label: 'Password',
                hint: '••••••••••••••••',
                obscureText: _obscurePassword,
                prefixIcon: Icons.lock_outline_rounded,
                suffix: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed:
                      widget.onForgotPassword ??
                      () => _showMessage(
                        'Password reset will be available soon.',
                      ),
                  child: const Text('Forgot Password?'),
                ),
              ),
              const SizedBox(height: 4),
              _PrimaryButton(onPressed: _signIn, isLoading: _isSubmitting),
              const SizedBox(height: 22),
              const _OrDivider(),
              const SizedBox(height: 18),
              _SocialButton(
                icon: Icons.key_rounded,
                iconColor: AppColors.primaryLight,
                label: 'Continue with Passkey',
                onPressed: widget.onPasskeyLogin == null
                    ? null
                    : () => _signInWithPasskey(),
              ),
              const SizedBox(height: 10),
              _SocialButton(
                icon: Icons.apple,
                label: 'Continue with Apple',
                onPressed: () =>
                    _showMessage('Apple sign-in will be available soon.'),
              ),
              const SizedBox(height: 10),
              _SocialButton(
                icon: Icons.g_mobiledata_rounded,
                iconColor: const Color(0xFFEA4335),
                label: 'Continue with Google',
                onPressed: () =>
                    _showMessage('Google sign-in will be available soon.'),
              ),
              const SizedBox(height: 10),
              _SocialButton(
                icon: Icons.phone_iphone_rounded,
                iconColor: AppColors.primaryLight,
                label: 'Continue with Phone',
                onPressed:
                    widget.onPhoneLogin ??
                    () => _showMessage('Phone sign-in will be available soon.'),
              ),
              const SizedBox(height: 20),
              Container(height: 1, color: AppColors.surfaceBorder),
              const SizedBox(height: 18),
              const Text(
                "Don't have an account?",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              TextButton(
                onPressed:
                    widget.onCreateAccount ??
                    () => _showMessage(
                      'Account creation will be available soon.',
                    ),
                child: const Text(
                  'Create Account',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.onSignIn?.call(
        _emailController.text,
        _passwordController.text,
      );
      if (!mounted) return;
      if (widget.onAuthenticated != null) {
        widget.onAuthenticated!();
      } else {
        _showMessage('Authentication setup is incomplete.');
      }
    } catch (_) {
      if (mounted) _showMessage('Please enter your email and password.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _signInWithPasskey() async {
    if (_isSubmitting || widget.onPasskeyLogin == null) return;
    setState(() => _isSubmitting = true);
    try {
      final email = _emailController.text.trim();
      await widget.onPasskeyLogin!(email: email.isEmpty ? null : email);
      if (!mounted) return;
      widget.onAuthenticated?.call();
    } catch (error) {
      if (mounted) _showMessage(_passkeyError(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _passkeyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('cancel')) return 'Passkey işlemi iptal edildi.';
    if (message.contains('domain-not-associated')) {
      return 'Bu uygulama alan adıyla doğrulanmamış. Lütfen destek ekibiyle iletişime geçin.';
    }
    if (message.contains('no-credentials'))
      return 'Bu cihazda kullanılabilir bir passkey bulunamadı.';
    return 'Passkey ile giriş tamamlanamadı. Şifrenizle tekrar deneyin.';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SoftGradientBackground extends StatelessWidget {
  const _SoftGradientBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFFFFF),
                AppColors.background,
                Color(0xFFF0EDFF),
              ],
            ),
          ),
        ),
        const Positioned(
          top: -95,
          right: -70,
          child: _BlurCircle(color: AppColors.primary, size: 240),
        ),
        const Positioned(
          bottom: 30,
          left: -105,
          child: _BlurCircle(color: AppColors.accentRose, size: 260),
        ),
        Positioned(
          top: 300,
          right: -80,
          child: _BlurCircle(
            color: AppColors.accentEmerald.withValues(alpha: 0.35),
            size: 180,
          ),
        ),
      ],
    );
  }
}

class _BlurCircle extends StatelessWidget {
  const _BlurCircle({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.40),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          '🇹🇷  TurkSquare',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Your Turkish Community in America',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 20),
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.primaryLight, AppColors.primary],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 24,
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.public_rounded, color: Colors.white, size: 47),
          ),
        ),
      ],
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.prefixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textMuted),
            prefixIcon: Icon(
              prefixIcon,
              color: AppColors.textSecondary,
              size: 20,
            ),
            suffixIcon: suffix,
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.18),
            contentPadding: const EdgeInsets.symmetric(vertical: 17),
            enabledBorder: _border(AppColors.surfaceBorder),
            focusedBorder: _border(AppColors.primaryLight),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: color),
  );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.onPressed, required this.isLoading});
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryLight, AppColors.primary],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          minimumSize: const Size(0, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Sign In',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: AppColors.surfaceBorder)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR CONTINUE WITH',
            style: TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppColors.surfaceBorder)),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.iconColor,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: iconColor ?? AppColors.textPrimary, size: 22),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: AppColors.surfaceBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}

class _TrustIndicators extends StatelessWidget {
  const _TrustIndicators();
  @override
  Widget build(BuildContext context) {
    const items = [
      'Secure Login',
      'End-to-End Encryption',
      'Trusted by Turkish Community',
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: items
          .map((item) => _TrustItem(label: item))
          .toList(growable: false),
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.check_circle_rounded,
          color: AppColors.accentEmerald,
          size: 14,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
        ),
      ],
    );
  }
}
