import 'package:flutter/material.dart';

import '../features/auth/application/auth_controller.dart';
import 'router/app_router.dart';
import 'router/app_routes.dart';
import 'theme/app_theme.dart';

class AmericaHubApp extends StatelessWidget {
  const AmericaHubApp({super.key, required this.authController});

  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TurkSquare',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: AppRoutes.startup,
      onGenerateRoute: AppRouter(
        authController: authController,
      ).onGenerateRoute,
    );
  }
}
