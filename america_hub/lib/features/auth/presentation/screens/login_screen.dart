import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/network/api_exception.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.onCheckEmailStatus,
    this.initialEmail,
    this.onSignIn,
    this.onAuthenticated,
    this.onForgotPassword,
    this.onCreateAccount,
    this.onRegisterWithEmail,
    this.onVerificationRequired,
    this.onPhoneLogin,
    this.onPasskeyLogin,
    this.onTermsOfService,
    this.onPrivacyPolicy,
  });

  final Future<bool> Function(String email)? onCheckEmailStatus;
  final String? initialEmail;
  final Future<void> Function(String email, String password)? onSignIn;
  final VoidCallback? onAuthenticated;
  /// Receives the address already typed on the first step, so the reset
  /// screen does not ask for something the person just entered.
  final void Function(String email)? onForgotPassword;
  final VoidCallback? onCreateAccount;
  final Future<void> Function(String email)? onRegisterWithEmail;

  /// Reached when the server refuses the password because the address was
  /// never verified. Without it the person is stuck on a screen whose only
  /// action can never succeed.
  final void Function(String email)? onVerificationRequired;
  final VoidCallback? onPhoneLogin;
  final Future<void> Function({String? email})? onPasskeyLogin;
  final VoidCallback? onTermsOfService;
  final VoidCallback? onPrivacyPolicy;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isExistingUser = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail?.trim() ?? '';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isExistingUser = _isExistingUser;
    final title = isExistingUser ? 'Giriş yap' : 'Hesap oluştur';
    final subtitle = isExistingUser
        ? 'Şifrenizle devam edin.'
        : 'Bu uygulamaya kaydolmak için e-posta adresinizi girin';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 330 / 252,
                      child: Image.asset(
                        'assets/images/auth/istanbul_galata.png',
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        semanticLabel: 'İstanbul Galata manzarası',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _EmailField(
                    controller: _emailController,
                    enabled: !isExistingUser && !_isLoading,
                    errorText: _emailError,
                    onChanged: (_) {
                      if (_emailError != null) {
                        setState(() => _emailError = null);
                      }
                    },
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: isExistingUser
                        ? Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: _PasswordStep(
                              controller: _passwordController,
                              obscurePassword: _obscurePassword,
                              enabled: !_isLoading,
                              onToggleObscure: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              onChangeEmail: _changeEmail,
                              onForgotPassword:
                                  widget.onForgotPassword == null
                                  ? null
                                  : () => widget.onForgotPassword!(
                                      _emailController.text.trim(),
                                    ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 16),
                  _ContinueButton(
                    isLoading: _isLoading,
                    label: isExistingUser ? 'Giriş yap' : 'Devam et',
                    onPressed: isExistingUser ? _signIn : _continueWithEmail,
                  ),
                  const SizedBox(height: 24),
                  const _DividerLabel(label: 'veya'),
                  const SizedBox(height: 24),
                  _ProviderButton(
                    icon: const FaIcon(
                      FontAwesomeIcons.google,
                      size: 20,
                      color: Color(0xFF4285F4),
                    ),
                    label: 'Google ile devam et',
                    onPressed: _showProviderUnavailable,
                  ),
                  const SizedBox(height: 10),
                  _ProviderButton(
                    icon: const FaIcon(FontAwesomeIcons.apple, size: 20),
                    label: 'Apple ile devam et',
                    onPressed: _showProviderUnavailable,
                  ),
                  const SizedBox(height: 10),
                  _ProviderButton(
                    icon: const Icon(Icons.phone_outlined, size: 22),
                    label: 'Telefonla devam et',
                    onPressed: _showProviderUnavailable,
                  ),
                  if (widget.onPasskeyLogin != null) ...[
                    const SizedBox(height: 10),
                    _ProviderButton(
                      icon: const Icon(Icons.key_outlined, size: 21),
                      label: 'Passkey ile devam et',
                      onPressed: _signInWithPasskey,
                    ),
                  ],
                  const SizedBox(height: 30),
                  _LegalNotice(
                    onTermsOfService: widget.onTermsOfService,
                    onPrivacyPolicy: widget.onPrivacyPolicy,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _continueWithEmail() async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      setState(() => _emailError = 'Geçerli bir e-posta adresi girin.');
      return;
    }
    final checkEmailStatus = widget.onCheckEmailStatus;
    if (checkEmailStatus == null) {
      _showMessage('E-posta kontrolü şu anda kullanılamıyor.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final exists = await checkEmailStatus(email);
      if (!mounted) return;
      if (exists) {
        setState(() => _isExistingUser = true);
      } else {
        final register = widget.onRegisterWithEmail;
        if (register != null) {
          await register(email);
        } else {
          widget.onCreateAccount?.call();
        }
      }
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signIn() async {
    if (_isLoading) return;
    final password = _passwordController.text;
    if (password.isEmpty) {
      _showMessage('Şifrenizi girin.');
      return;
    }
    if (widget.onSignIn == null) {
      _showMessage('Giriş servisi yapılandırılmamış.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await widget.onSignIn!(_emailController.text.trim(), password);
      if (!mounted) return;
      widget.onAuthenticated?.call();
    } catch (error) {
      if (!mounted) return;
      final resume = widget.onVerificationRequired;
      if (resume != null &&
          error is ApiException &&
          error.code == 'EMAIL_VERIFICATION_REQUIRED') {
        resume(_emailController.text.trim());
        return;
      }
      _showMessage(_messageFor(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithPasskey() async {
    final callback = widget.onPasskeyLogin;
    if (callback == null || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      await callback(email: email.isEmpty ? null : email);
      if (!mounted) return;
      widget.onAuthenticated?.call();
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _changeEmail() {
    setState(() {
      _isExistingUser = false;
      _passwordController.clear();
      _obscurePassword = true;
    });
  }

  void _showProviderUnavailable() =>
      _showMessage('Bu giriş yöntemi yakında kullanılabilir olacak.');

  void _showMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  bool _isValidEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  String _messageFor(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}

class _EmailField extends StatelessWidget {
  const _EmailField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? errorText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          enabled: enabled,
          onChanged: onChanged,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          style: GoogleFonts.inter(fontSize: 14, color: Colors.black),
          decoration: _inputDecoration(
            hint: 'email@domain.com',
            errorText: errorText,
          ),
        ),
      ],
    );
  }
}

class _PasswordStep extends StatelessWidget {
  const _PasswordStep({
    required this.controller,
    required this.obscurePassword,
    required this.enabled,
    required this.onToggleObscure,
    required this.onChangeEmail,
    this.onForgotPassword,
  });

  final TextEditingController controller;
  final bool obscurePassword;
  final bool enabled;
  final VoidCallback onToggleObscure;
  final VoidCallback onChangeEmail;
  final VoidCallback? onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscurePassword,
          enableInteractiveSelection: false,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          style: GoogleFonts.inter(fontSize: 14, color: Colors.black),
          decoration: _inputDecoration(
            hint: 'Şifreniz',
            suffixIcon: IconButton(
              tooltip: obscurePassword ? 'Şifreyi göster' : 'Şifreyi gizle',
              onPressed: enabled ? onToggleObscure : null,
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 2,
          children: [
            TextButton(
              onPressed: enabled ? onChangeEmail : null,
              child: const Text('E-postayı değiştir'),
            ),
            TextButton(
              onPressed: enabled ? onForgotPassword : null,
              child: const Text('Şifremi unuttum'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black,
          disabledBackgroundColor: Colors.black54,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFE6E6E6))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: const Color(0xFF828282),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFFE6E6E6))),
      ],
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Widget icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEEEEEE),
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _LegalNotice extends StatelessWidget {
  const _LegalNotice({this.onTermsOfService, this.onPrivacyPolicy});

  final VoidCallback? onTermsOfService;
  final VoidCallback? onPrivacyPolicy;

  @override
  Widget build(BuildContext context) {
    final muted = GoogleFonts.inter(
      color: const Color(0xFF828282),
      fontSize: 12,
      height: 1.5,
    );
    final link = muted.copyWith(color: Colors.black);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Devam ederek ', style: muted),
        _LegalLink(
          label: 'Kullanım Koşulları',
          onPressed: onTermsOfService,
          style: link,
        ),
        Text(' ve ', style: muted),
        _LegalLink(
          label: 'Gizlilik Politikası',
          onPressed: onPrivacyPolicy,
          style: link,
        ),
        Text("'nı kabul etmiş olursunuz.", style: muted),
      ],
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({
    required this.label,
    required this.onPressed,
    required this.style,
  });

  final String label;
  final VoidCallback? onPressed;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Text(
        label,
        style: style.copyWith(decoration: TextDecoration.underline),
      ),
    );
  }
}

InputDecoration _inputDecoration({
  required String hint,
  String? errorText,
  Widget? suffixIcon,
}) => InputDecoration(
  hintText: hint,
  hintStyle: GoogleFonts.inter(color: const Color(0xFF828282), fontSize: 14),
  errorText: errorText,
  errorStyle: GoogleFonts.inter(fontSize: 12),
  filled: true,
  fillColor: Colors.white,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  suffixIcon: suffixIcon,
  enabledBorder: _outline(const Color(0xFFDFDFDF)),
  focusedBorder: _outline(Colors.black),
  errorBorder: _outline(Colors.red.shade700),
  focusedErrorBorder: _outline(Colors.red.shade700),
);

OutlineInputBorder _outline(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(8),
  borderSide: BorderSide(color: color),
);
