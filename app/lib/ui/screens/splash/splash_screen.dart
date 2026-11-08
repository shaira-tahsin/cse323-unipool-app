import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _waitForAuthAndCheck();
  }

  Future<void> _waitForAuthAndCheck() async {
    // Wait for Firebase to restore auth state (one-time emission)
    final user = await FirebaseAuth.instance.authStateChanges().first;

    if (!mounted || _handled) return;
    _handled = true;

    if (user == null) {
      // Not logged in — let router redirect to GetStarted
      ref.read(hasProfileProvider.notifier).state = false;
    } else {
      // Logged in — check Firestore for profile
      await ref.read(authNotifierProvider.notifier).checkProfile(user.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
                children: [
                  TextSpan(text: 'UniP'),
                  WidgetSpan(
                    child: Icon(
                      Icons.directions_car,
                      color: AppColors.white,
                      size: 40,
                    ),
                  ),
                  TextSpan(text: 'l'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ride together',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
