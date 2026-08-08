import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.email,
    required this.onConfirm,
    required this.onResend,
    required this.onVerified,
  });

  final String email;
  final Future<void> Function(String email, String code) onConfirm;
  final Future<void> Function(String email) onResend;
  final VoidCallback onVerified;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  static const _codeLength = 6;
  static const _codeTtlSeconds = 59;
  final _controllers = List.generate(
    _codeLength,
    (_) => TextEditingController(),
  );
  final _focusNodes = List.generate(_codeLength, (_) => FocusNode());
  Timer? _timer;
  int _resendSeconds = _codeTtlSeconds;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 28),
                  Text(
                    'Doğrulama kodunu girin',
                    style: GoogleFonts.inter(
                      color: Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: GoogleFonts.inter(
                        color: const Color(0xFF555555),
                        fontSize: 15,
                        height: 1.5,
                      ),
                      children: [
                        const TextSpan(
                          text: 'Şu adrese gönderilen 6 haneli kodu girin:\n',
                        ),
                        TextSpan(
                          text: _maskedEmail(widget.email),
                          style: const TextStyle(
                            color: Color(0xFFFF0050),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(
                      _codeLength,
                      (index) => SizedBox(
                        width: 42,
                        child: TextField(
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          enabled: !_isLoading,
                          autofocus: index == 0,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          textInputAction: index == _codeLength - 1
                              ? TextInputAction.done
                              : TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(1),
                          ],
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: const InputDecoration(
                            counterText: '',
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF777777)),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.black,
                                width: 2,
                              ),
                            ),
                          ),
                          onChanged: (value) {
                            if (value.isNotEmpty && index < _codeLength - 1) {
                              _focusNodes[index + 1].requestFocus();
                            }
                            if (_code.length == _codeLength) {
                              _verify();
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _verify,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF0050),
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
                              'Doğrula',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 34),
                  Text(
                    'Kod gelmedi mi?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: const Color(0xFF828282),
                      fontSize: 12,
                    ),
                  ),
                  TextButton(
                    onPressed: _resendSeconds == 0 && !_isLoading
                        ? _resend
                        : null,
                    child: Text(
                      _resendSeconds == 0
                          ? 'Kodu yeniden gönder'
                          : 'Yeni kod için $_resendSeconds sn bekleyin',
                      style: GoogleFonts.inter(
                        color: const Color(0xFFFF0050),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('E-posta adresini değiştir'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _code => _controllers.map((controller) => controller.text).join();

  Future<void> _verify() async {
    if (_isLoading) return;
    if (_code.length != _codeLength) {
      _showMessage('6 haneli doğrulama kodunu girin.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await widget.onConfirm(widget.email, _code);
      if (!mounted) return;
      widget.onVerified();
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _isLoading = true);
    try {
      await widget.onResend(widget.email);
      if (!mounted) return;
      for (final controller in _controllers) {
        controller.clear();
      }
      _focusNodes.first.requestFocus();
      _startResendTimer();
      _showMessage('Yeni doğrulama kodu gönderildi.');
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = _codeTtlSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendSeconds == 0) {
        timer.cancel();
        return;
      }
      setState(() => _resendSeconds -= 1);
    });
  }

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
