import 'package:flutter/material.dart';

import '../../../../app/router/app_routes.dart';
import '../../../auth/application/auth_controller.dart';

class AuthenticatedHomeScreen extends StatefulWidget {
  const AuthenticatedHomeScreen({super.key, required this.authController});

  final AuthController authController;

  @override
  State<AuthenticatedHomeScreen> createState() =>
      _AuthenticatedHomeScreenState();
}

class _AuthenticatedHomeScreenState extends State<AuthenticatedHomeScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    await widget.authController.signOut();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.authController.user?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('TurkSquare'),
        actions: [
          IconButton(
            tooltip: 'Güvenli çıkış yap',
            onPressed: _signingOut ? null : _signOut,
            icon: _signingOut
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_user_outlined, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Oturumunuz güvenle açıldı.',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(email, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              const Text(
                'Akış modülü ayrı ve küçük bir sonraki değişiklikte eklenecek.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
