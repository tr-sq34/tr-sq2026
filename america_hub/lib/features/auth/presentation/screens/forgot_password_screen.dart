import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/services/password_policy.dart';

/// Password reset in three steps: prove you can read the mailbox, then choose a
/// password. The emailed code lives 59 seconds, but redeeming it mints a ticket
/// that carries the rest of the flow — so the countdown never races the person
/// typing a new password, and the code stays as short-lived as it should be.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    required this.onRequestReset,
    required this.onVerifyCode,
    required this.onConfirmReset,
    required this.onCompleted,
    this.initialEmail,
  });

  final Future<void> Function(String email) onRequestReset;
  final Future<String> Function(String email, String code) onVerifyCode;
  final Future<void> Function(String ticket, String password) onConfirmReset;
  final void Function(String email) onCompleted;
  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _ResetStep { email, code, password }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const _codeLength = 6;
  static const _codeTtlSeconds = 59;
  static const _accent = Color(0xFFFF0050);

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _codeControllers = List.generate(
    _codeLength,
    (_) => TextEditingController(),
  );
  final _codeFocusNodes = List.generate(_codeLength, (_) => FocusNode());

  _ResetStep _step = _ResetStep.email;
  Timer? _timer;
  int _secondsLeft = 0;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _ticket;
  String? _emailError;
  String? _codeError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _email.text = widget.initialEmail ?? '';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    for (final controller in _codeControllers) {
      controller.dispose();
    }
    for (final focusNode in _codeFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  bool get _codeExpired => _secondsLeft == 0;
  String get _code => _codeControllers.map((c) => c.text).join();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isLoading ? null : _goBack,
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    switch (_step) {
                      _ResetStep.email => 'Parolanızı sıfırlayın',
                      _ResetStep.code => 'Doğrulama kodunu girin',
                      _ResetStep.password => 'Yeni parolanızı belirleyin',
                    },
                    style: GoogleFonts.inter(
                      color: Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _subtitle(),
                  const SizedBox(height: 28),
                  switch (_step) {
                    _ResetStep.email => _emailStep(),
                    _ResetStep.code => _codeStep(),
                    _ResetStep.password => _passwordStep(),
                  },
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _subtitle() {
    final muted = GoogleFonts.inter(
      color: const Color(0xFF555555),
      fontSize: 15,
      height: 1.5,
    );
    return switch (_step) {
      _ResetStep.email => Text(
        'Hesabınıza bağlı e-posta adresini girin. Adrese 6 haneli bir kod göndereceğiz.',
        style: muted,
      ),
      _ResetStep.code => Text.rich(
        TextSpan(
          style: muted,
          children: [
            const TextSpan(text: 'Şu adrese gönderilen 6 haneli kodu girin:\n'),
            TextSpan(
              text: _maskedEmail(_email.text.trim()),
              style: const TextStyle(
                color: _accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      _ResetStep.password => Text(
        'Parolanızı iki kez girin. Kaydettiğinizde bu hesaptaki tüm açık oturumlar kapatılır.',
        style: muted,
      ),
    };
  }

  // ---------------------------------------------------------------- step 1

  Widget _emailStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _email,
        enabled: !_isLoading,
        autofocus: widget.initialEmail == null,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.email],
        onSubmitted: (_) => _requestCode(),
        onChanged: (_) {
          if (_emailError != null) setState(() => _emailError = null);
        },
        style: GoogleFonts.inter(fontSize: 14, color: Colors.black),
        decoration: _inputDecoration(
          hint: 'email@domain.com',
          errorText: _emailError,
        ),
      ),
      const SizedBox(height: 24),
      _primaryButton(label: 'Kod gönder', onPressed: _requestCode),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _isLoading ? null : _goBack,
        child: Text(
          'Girişe dön',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF555555)),
        ),
      ),
    ],
  );

  // ---------------------------------------------------------------- step 2

  Widget _codeStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(_codeLength, _codeBox),
      ),
      if (_codeError != null) ...[
        const SizedBox(height: 12),
        Text(
          _codeError!,
          style: GoogleFonts.inter(fontSize: 12, color: Colors.red.shade700),
        ),
      ],
      const SizedBox(height: 24),
      _primaryButton(
        label: 'Doğrula',
        onPressed: _codeExpired ? null : _verifyCode,
      ),
      const SizedBox(height: 24),
      // The countdown is the client's own, started when the code was sent. The
      // server deliberately answers "invalid or expired" for both cases, so the
      // timer — not the response — is what tells someone a resend is due.
      Text(
        _codeExpired
            ? 'Kodun süresi doldu.'
            : 'Kod $_secondsLeft saniye daha geçerli.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          color: _codeExpired ? Colors.red.shade700 : const Color(0xFF828282),
          fontSize: 12,
          fontWeight: _codeExpired ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      TextButton(
        onPressed: _codeExpired && !_isLoading ? _resendCode : null,
        child: Text(
          'Kodu yeniden gönder',
          style: GoogleFonts.inter(
            color: _codeExpired ? _accent : const Color(0xFFBBBBBB),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      TextButton(
        onPressed: _isLoading ? null : _backToEmail,
        child: Text(
          'E-posta adresini değiştir',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF555555)),
        ),
      ),
    ],
  );

  Widget _codeBox(int index) => SizedBox(
    width: 42,
    child: TextField(
      controller: _codeControllers[index],
      focusNode: _codeFocusNodes[index],
      enabled: !_isLoading && !_codeExpired,
      autofocus: index == 0,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      textInputAction: index == _codeLength - 1
          ? TextInputAction.done
          : TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w500),
      decoration: const InputDecoration(
        counterText: '',
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF777777)),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.black, width: 2),
        ),
      ),
      onChanged: (value) => _onCodeChanged(index, value),
    ),
  );

  /// Handles both typing and pasting. Codes arrive by email, and people paste
  /// all six digits into whichever box happens to be focused; splitting the
  /// value across the remaining boxes is what they expect to happen.
  void _onCodeChanged(int index, String value) {
    if (_codeError != null) setState(() => _codeError = null);
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var offset = 0; index + offset < _codeLength; offset++) {
        _codeControllers[index + offset].text = offset < digits.length
            ? digits[offset]
            : '';
      }
      final next = (index + digits.length).clamp(0, _codeLength - 1);
      _codeFocusNodes[next].requestFocus();
    } else if (value.isNotEmpty && index < _codeLength - 1) {
      _codeFocusNodes[index + 1].requestFocus();
    }
    if (_code.length == _codeLength) _verifyCode();
  }

  // ---------------------------------------------------------------- step 3

  Widget _passwordStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _password,
        enabled: !_isLoading,
        autofocus: true,
        obscureText: _obscurePassword,
        enableInteractiveSelection: false,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.newPassword],
        onChanged: (_) => setState(() => _passwordError = null),
        style: GoogleFonts.inter(fontSize: 14, color: Colors.black),
        decoration: _inputDecoration(
          hint: 'Yeni parola',
          suffixIcon: _visibilityToggle(
            obscured: _obscurePassword,
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _confirmPassword,
        enabled: !_isLoading,
        obscureText: _obscureConfirmPassword,
        enableInteractiveSelection: false,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.newPassword],
        onChanged: (_) => setState(() => _passwordError = null),
        onSubmitted: (_) => _confirmReset(),
        style: GoogleFonts.inter(fontSize: 14, color: Colors.black),
        decoration: _inputDecoration(
          hint: 'Yeni parolayı tekrar girin',
          errorText: _passwordError,
          suffixIcon: _visibilityToggle(
            obscured: _obscureConfirmPassword,
            onPressed: () => setState(
              () => _obscureConfirmPassword = !_obscureConfirmPassword,
            ),
          ),
        ),
      ),
      const SizedBox(height: 18),
      _rule(
        'En az ${PasswordPolicy.minLength} karakter',
        _password.text.trim().length >= PasswordPolicy.minLength,
      ),
      _rule(
        'E-posta adresinizi veya adınızı içermiyor',
        PasswordPolicy.validate(_password.text, email: _email.text.trim()) ==
                null ||
            _password.text.trim().length < PasswordPolicy.minLength,
      ),
      _rule(
        'İki alan birbiriyle aynı',
        _password.text.isNotEmpty && _password.text == _confirmPassword.text,
      ),
      const SizedBox(height: 24),
      _primaryButton(label: 'Parolayı güncelle', onPressed: _confirmReset),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _isLoading ? null : _backToEmail,
        child: Text(
          'Baştan başla',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF555555)),
        ),
      ),
    ],
  );

  Widget _rule(String label, bool satisfied) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(
          satisfied ? Icons.check_circle : Icons.circle_outlined,
          size: 16,
          color: satisfied ? const Color(0xFF1E9E5A) : const Color(0xFFBBBBBB),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: satisfied
                  ? const Color(0xFF1E9E5A)
                  : const Color(0xFF828282),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _visibilityToggle({
    required bool obscured,
    required VoidCallback onPressed,
  }) => IconButton(
    tooltip: obscured ? 'Parolayı göster' : 'Parolayı gizle',
    onPressed: _isLoading ? null : onPressed,
    icon: Icon(
      obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
    ),
  );

  Widget _primaryButton({required String label, VoidCallback? onPressed}) =>
      SizedBox(
        height: 46,
        child: FilledButton(
          onPressed: _isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            disabledBackgroundColor: const Color(0xFFE7E7E7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  label,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
        ),
      );

  // ---------------------------------------------------------------- actions

  Future<void> _requestCode() async {
    final email = _email.text.trim();
    if (!_looksLikeEmail(email)) {
      setState(() => _emailError = 'Geçerli bir e-posta adresi girin.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _emailError = null;
    });
    try {
      await widget.onRequestReset(email);
      if (!mounted) return;
      _clearCode();
      setState(() => _step = _ResetStep.code);
      _startCountdown();
    } catch (error) {
      if (mounted) setState(() => _emailError = _messageOf(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() => _isLoading = true);
    try {
      await widget.onRequestReset(_email.text.trim());
      if (!mounted) return;
      _clearCode();
      setState(() => _codeError = null);
      _startCountdown();
      _codeFocusNodes.first.requestFocus();
      _showMessage('Yeni kod gönderildi.');
    } catch (error) {
      if (mounted) setState(() => _codeError = _messageOf(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_isLoading) return;
    if (_code.length != _codeLength) {
      setState(() => _codeError = '6 haneli kodu girin.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _codeError = null;
    });
    try {
      final ticket = await widget.onVerifyCode(_email.text.trim(), _code);
      if (!mounted) return;
      // The code is spent server-side now, right or wrong, so the countdown has
      // nothing left to guard.
      _timer?.cancel();
      setState(() {
        _ticket = ticket;
        _step = _ResetStep.password;
      });
    } catch (error) {
      if (!mounted) return;
      _clearCode();
      setState(() => _codeError = _messageOf(error));
      if (!_codeExpired) _codeFocusNodes.first.requestFocus();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmReset() async {
    final ticket = _ticket;
    if (ticket == null) {
      _backToEmail();
      return;
    }
    final password = _password.text;
    if (PasswordPolicy.validate(password, email: _email.text.trim())
        case final error?) {
      setState(() => _passwordError = error);
      return;
    }
    if (password != _confirmPassword.text) {
      setState(() => _passwordError = 'Parolalar birbiriyle eşleşmiyor.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _passwordError = null;
    });
    try {
      await widget.onConfirmReset(ticket, password);
      if (!mounted) return;
      widget.onCompleted(_email.text.trim());
    } catch (error) {
      if (!mounted) return;
      // A rejected password costs the ticket, so there is nothing left to retry
      // with; the honest move is to send the person back for a fresh code.
      setState(() {
        _ticket = null;
        _passwordError = _messageOf(error);
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _backToEmail() {
    _timer?.cancel();
    _clearCode();
    _password.clear();
    _confirmPassword.clear();
    setState(() {
      _step = _ResetStep.email;
      _ticket = null;
      _secondsLeft = 0;
      _codeError = null;
      _passwordError = null;
    });
  }

  void _goBack() {
    if (_step == _ResetStep.email) {
      Navigator.of(context).maybePop();
      return;
    }
    _backToEmail();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _codeTtlSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  void _clearCode() {
    for (final controller in _codeControllers) {
      controller.clear();
    }
  }

  bool _looksLikeEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  String _messageOf(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  String _maskedEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2 || parts.first.isEmpty) return email;
    final local = parts.first;
    final visible = local.length <= 2 ? local[0] : local.substring(0, 2);
    return '$visible***@${parts.last}';
  }

  void _showMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
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
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  suffixIcon: suffixIcon,
  enabledBorder: _outline(const Color(0xFFDFDFDF)),
  focusedBorder: _outline(Colors.black),
  disabledBorder: _outline(const Color(0xFFEFEFEF)),
  errorBorder: _outline(Colors.red.shade700),
  focusedErrorBorder: _outline(Colors.red.shade700),
);

OutlineInputBorder _outline(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(8),
  borderSide: BorderSide(color: color),
);
