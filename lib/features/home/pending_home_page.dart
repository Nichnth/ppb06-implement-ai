import 'package:flutter/material.dart';

import '../auth/auth_service.dart';

class PendingHomePage extends StatelessWidget {
  const PendingHomePage({
    super.key,
    required this.fullName,
    required this.email,
    required this.authService,
  });

  final String? fullName;
  final String? email;
  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    final displayName = fullName?.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ColorCam'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: authService.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Welcome ${displayName?.isNotEmpty == true ? displayName : email ?? ''}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Firebase setup is ready. We can plug in your custom home design next.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
