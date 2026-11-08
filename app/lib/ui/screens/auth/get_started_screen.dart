import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/auth_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

class GetStartedScreen extends ConsumerStatefulWidget {
  const GetStartedScreen({super.key});

  @override
  ConsumerState<GetStartedScreen> createState() => _GetStartedScreenState();
}

class _GetStartedScreenState extends ConsumerState<GetStartedScreen> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    ref.listen(authNotifierProvider, (_, next) {
      next.whenOrNull(
        error: (e, _) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        ),
      );
    });

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const Spacer(),
            // Logo
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
            const Spacer(),
            // Google button
            _AuthButton(
              onPressed: authState.isLoading
                  ? null
                  : () async {
                      ref.read(hasProfileProvider.notifier).state = null;
                      await ref
                          .read(authNotifierProvider.notifier)
                          .signInWithGoogle();
                      final authUser =
                          ref.read(authStateProvider).valueOrNull;
                      if (authUser != null) {
                        await ref
                            .read(authNotifierProvider.notifier)
                            .checkProfile(authUser.uid);
                      }
                    },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset('assets/icons/google.svg', height: 20),
                  const SizedBox(width: 12),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'or',
              style: TextStyle(color: AppColors.white),
            ),
            const SizedBox(height: 12),
            // Student email button
            _AuthButton(
              onPressed: authState.isLoading
                  ? null
                  : () => _showEmailLoginDialog(context),
              child: authState.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Log in with student email',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  // ── Email login dialog ──────────────────────────────────────────────────
  //
  // Key fix: `ref` comes from ConsumerState, which lives as long as the widget
  // is in the tree. The old top-level function captured `ref` from a
  // ConsumerWidget.build call, which could be invalidated mid-dialog, causing
  // the `_dependents.isEmpty is not true` assertion crash.

  Future<void> _showEmailLoginDialog(BuildContext context) async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _EmailLoginDialog(
        formKey: formKey,
        emailCtrl: emailCtrl,
        passCtrl: passCtrl,
        onSubmit: (email, password) async {
          await ref
              .read(authNotifierProvider.notifier)
              .signInWithEmail(email, password);

          // checkProfile is already called inside signInWithEmail notifier,
          // so routing will happen automatically via the router redirect.
          if (ctx.mounted) Navigator.of(ctx).pop();
        },
      ),
    );

    emailCtrl.dispose();
    passCtrl.dispose();
  }
}

// ── Extracted stateful dialog widget ──────────────────────────────────────
//
// Using a proper StatefulWidget for the dialog means loading state is
// self-contained and doesn't rely on ref or StatefulBuilder.

class _EmailLoginDialog extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final Future<void> Function(String email, String password) onSubmit;

  const _EmailLoginDialog({
    required this.formKey,
    required this.emailCtrl,
    required this.passCtrl,
    required this.onSubmit,
  });

  @override
  State<_EmailLoginDialog> createState() => _EmailLoginDialogState();
}

class _EmailLoginDialogState extends State<_EmailLoginDialog> {
  bool _loading = false;
  String? _error;

  Future<void> _handleLogin() async {
    if (!widget.formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        widget.emailCtrl.text.trim(),
        widget.passCtrl.text,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log in with student email'),
      content: Form(
        key: widget.formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: widget.emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'you@northsouth.edu',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter your email';
                if (!v.contains('@northsouth.edu')) {
                  return 'Must be a @northsouth.edu address';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: widget.passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Enter your password' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _loading ? null : _handleLogin,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(
                  'Log in',
                  style: TextStyle(color: AppColors.primary),
                ),
        ),
      ],
    );
  }
}

// ── Shared auth button ─────────────────────────────────────────────────────

class _AuthButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;

  const _AuthButton({required this.onPressed, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: child,
      ),
    );
  }
}
