import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/auth_validator.dart';
import '../../../data/models/user_model.dart';
import '../../../providers/auth_provider.dart';

class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() =>
      _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _licenceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final authUser = ref.read(authStateProvider).valueOrNull;
    if (authUser != null) {
      _nameController.text = _cleanDisplayName(authUser.displayName ?? '');
      _emailController.text = authUser.email ?? '';
    }

    // If profile check is still running, wait for it.
    // If it completes with true, redirect to Home immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _guardExistingUser();
    });
  }

  Future<void> _guardExistingUser() async {
    final authUser = ref.read(authStateProvider).valueOrNull;
    if (authUser == null) return;

    // If hasProfile is already true, go home immediately
    final hasProfile = ref.read(hasProfileProvider);
    if (hasProfile == true) {
      if (mounted) context.go(AppRoutes.home);
      return;
    }

    // If still null (checking), wait for checkProfile to finish
    if (hasProfile == null) {
      await ref.read(authNotifierProvider.notifier).checkProfile(authUser.uid);
      if (!mounted) return;
      if (ref.read(hasProfileProvider) == true) {
        context.go(AppRoutes.home);
      }
    }
  }

  String _cleanDisplayName(String name) {
    return name.replaceAll(RegExp(r'\s+\d+$'), '').trim();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _licenceController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate()) return;

    final authUser = ref.read(authStateProvider).valueOrNull;
    if (authUser == null) return;

    final user = UserModel(
      uid: authUser.uid,
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      licencePlate: _licenceController.text.trim().isEmpty
          ? null
          : _licenceController.text.trim(),
      universityDomain: 'northsouth.edu',
      rating: 0.0,
      totalRides: 0,
      createdAt: DateTime.now(),
    );

    await ref.read(authNotifierProvider.notifier).createUserProfile(user);
  }

  Future<void> _cancel() async {
    await ref.read(authNotifierProvider.notifier).signOut();
    if (mounted) context.go(AppRoutes.getStarted);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: authState.isLoading ? null : _cancel,
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: AppColors.white,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      const Text(
                        'Create an Account',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _buildLabel('Enter your Name'),
                      _buildField(
                        controller: _nameController,
                        validator: AuthValidator.validateName,
                      ),
                      const SizedBox(height: 16),
                      _buildLabel('Enter your email'),
                      _buildField(
                        controller: _emailController,
                        validator: AuthValidator.validateEmail,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      _buildLabel('Enter your phone number'),
                      _buildField(
                        controller: _phoneController,
                        validator: AuthValidator.validatePhone,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      _buildLabel(
                          'Enter your License Plate Number\n(If you want to drive)'),
                      _buildField(
                        controller: _licenceController,
                        validator: null,
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: authState.isLoading ? null : _confirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.white,
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: authState.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Text(
                                  'Confirm',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.white),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.accent.withOpacity(0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        errorStyle: const TextStyle(color: Colors.redAccent),
      ),
    );
  }
}
