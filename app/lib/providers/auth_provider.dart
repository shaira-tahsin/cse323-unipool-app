import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/user_model.dart';
import '../data/repositories/auth_repository.dart';

// Repository provider
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

// Firebase auth state stream
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

// Tracks whether the current user has a Firestore profile.
// null  = not checked yet (checking in progress)
// false = checked, no profile (new user)
// true  = profile exists (existing user or just confirmed)
final hasProfileProvider = StateProvider<bool?>((ref) => null);

// Current user profile from Firestore
final userProfileProvider = FutureProvider<UserModel?>((ref) async {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) async {
      if (user == null) return null;
      return ref.read(authRepositoryProvider).getUserProfile(user.uid);
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

// Auth actions notifier
class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  final AuthRepository _repository;
  final Ref _ref;

  AuthNotifier(this._repository, this._ref)
      : super(const AsyncValue.data(null));

  // Called once on app start to check if profile exists for the signed-in user
  Future<void> checkProfile(String uid) async {
    final exists = await _repository.userProfileExists(uid);
    _ref.read(hasProfileProvider.notifier).state = exists;
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.signInWithGoogle());
    // After successful sign-in, check if profile exists
    if (!state.hasError) {
      final user = _repository.currentUser;
      if (user != null) {
        await checkProfile(user.uid);
      }
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repository.signInWithEmail(email, password),
    );
    // After successful sign-in, check if profile exists
    if (!state.hasError) {
      final user = _repository.currentUser;
      if (user != null) {
        await checkProfile(user.uid);
      }
    }
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    // Reset profile state on sign out
    _ref.read(hasProfileProvider.notifier).state = null;
    state = await AsyncValue.guard(() => _repository.signOut());
  }

  Future<void> createUserProfile(UserModel user) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repository.createUserProfile(user),
    );
    if (!state.hasError) {
      // Flip to true — router will redirect to Home
      _ref.read(hasProfileProvider.notifier).state = true;
    }
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<void>>((ref) {
  return AuthNotifier(ref.read(authRepositoryProvider), ref);
});
