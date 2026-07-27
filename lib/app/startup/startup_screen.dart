import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../features/auth/application/auth_controller.dart';
import '../router/app_routes.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key, required this.authController});

  final AuthController authController;

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    await widget.authController.restoreSession();
    if (!mounted) return;
    final destination = widget.authController.isAuthenticated ? AppRoutes.home : AppRoutes.login;
    Navigator.of(context).pushReplacementNamed(destination);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🇹🇷', style: TextStyle(fontSize: 42)),
            SizedBox(height: 12),
            Text('TurkSquare', style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
            SizedBox(height: 20),
            SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      ),
    );
  }
}
