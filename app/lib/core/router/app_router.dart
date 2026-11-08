import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../ui/screens/splash/splash_screen.dart';
import '../../ui/screens/auth/get_started_screen.dart';
import '../../ui/screens/auth/create_account_screen.dart';
import '../../ui/screens/home/home_screen.dart';
import '../../ui/screens/ride/offer_ride_screen.dart';
import '../../ui/screens/ride/join_ride_screen.dart';
import '../../ui/screens/ride/ride_results_screen.dart';
import '../../ui/screens/ride/driver_profile_screen.dart';
import '../../ui/screens/ride/active_ride_screen.dart';
import '../../ui/screens/ride/active_ride_map_screen.dart';
import '../../ui/screens/chat/chat_screen.dart';
import '../../ui/screens/history/ride_history_screen.dart';
import '../../ui/screens/profile/profile_screen.dart';
import '../../ui/screens/ride/ride_requests_screen.dart';
import '../../ui/screens/rating/rating_screen.dart';
import '../../ui/screens/notifications/notifications_screen.dart';

abstract class AppRoutes {
  static const splash = '/';
  static const getStarted = '/get-started';
  static const createAccount = '/create-account';
  static const home = '/home';
  static const offerRide = '/offer-ride';
  static const joinRide = '/join-ride';
  static const rideResults = '/ride-results';
  static const driverProfile = '/driver-profile';
  static const chat = '/chat';
  static const rideRequests = '/ride-requests/:rideId';
  static const rideHistory = '/ride-history';
  static const profile = '/profile';

  static const activeRide = '/active-ride/:rideId';       // driver
  static const activeRideMap = '/active-ride-map/:rideId'; // passenger
  static const rating = '/rating';                          // Step 10
  static const notifications = '/notifications';             // Step 11
}

final routerProvider = Provider<GoRouter>((ref) {
  final routerNotifier = _RouterNotifier(ref);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: routerNotifier,
    redirect: (context, state) {
      final hasProfile = ref.read(hasProfileProvider);
      final loc = state.matchedLocation;

      if (hasProfile == null) {
        return loc == AppRoutes.splash ? null : AppRoutes.splash;
      }

      final authAsync = ref.read(authStateProvider);
      final user = authAsync.valueOrNull;

      if (user == null) {
        return loc == AppRoutes.getStarted ? null : AppRoutes.getStarted;
      }

      if (!hasProfile) {
        return loc == AppRoutes.createAccount ? null : AppRoutes.createAccount;
      }

      if (loc == AppRoutes.splash ||
          loc == AppRoutes.getStarted ||
          loc == AppRoutes.createAccount) {
        return AppRoutes.home;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.getStarted,
        builder: (_, __) => const GetStartedScreen(),
      ),
      GoRoute(
        path: AppRoutes.createAccount,
        builder: (_, __) => const CreateAccountScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.offerRide,
        builder: (_, __) => const OfferRideScreen(),
      ),
      GoRoute(
        path: AppRoutes.joinRide,
        builder: (_, __) => const JoinRideScreen(),
      ),
      GoRoute(
        path: AppRoutes.rideResults,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};

          final depMs = extra['departureTime'] as int?;
          final departureTime = depMs != null
              ? DateTime.fromMillisecondsSinceEpoch(depMs)
              : null;

          return RideResultsScreen(
            fromName: extra['fromName'] as String? ?? '',
            toName: extra['toName'] as String? ?? '',
            fromLat: extra['fromLat'] as double?,
            fromLng: extra['fromLng'] as double?,
            toLat: extra['toLat'] as double?,
            toLng: extra['toLng'] as double?,
            departureTime: departureTime,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.driverProfile,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return DriverProfileScreen(rideId: extra['rideId'] as String);
        },
      ),
      GoRoute(
        path: AppRoutes.chat,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return ChatScreen(
            chatId: extra['chatId'] as String,
            otherUserName: extra['otherUserName'] as String,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.rideRequests,
        builder: (context, state) {
          final rideId = state.pathParameters['rideId']!;
          return RideRequestsScreen(rideId: rideId);
        },
      ),
      GoRoute(
        path: AppRoutes.rideHistory,
        builder: (_, __) => const RideHistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, __) => const ProfileScreen(),
      ),

      // NEW — Step 7d
      // Driver's active ride management screen
      GoRoute(
        path: AppRoutes.activeRide,
        builder: (context, state) {
          final rideId = state.pathParameters['rideId']!;
          return ActiveRideScreen(rideId: rideId);
        },
      ),
      // Passenger's live map screen
      GoRoute(
        path: AppRoutes.activeRideMap,
        builder: (context, state) {
          final rideId = state.pathParameters['rideId']!;
          return ActiveRideMapScreen(rideId: rideId);
        },
      ),
      // Step 10 — Rating
      GoRoute(
        path: AppRoutes.rating,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return RatingScreen(
            rideId: extra['rideId'] as String,
            toUid: extra['toUid'] as String,
            toName: extra['toName'] as String,
            role: extra['role'] as String,
          );
        },
      ),
      // Step 11 — Notifications
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, __) => const NotificationsScreen(),
      ),
    ],
  );
});

class _RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  _RouterNotifier(this._ref) {
    _ref.listen(authStateProvider, (_, __) => notifyListeners());
    _ref.listen(hasProfileProvider, (_, __) => notifyListeners());
  }
}
