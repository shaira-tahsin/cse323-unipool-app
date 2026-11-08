import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/router/app_router.dart';
import 'data/repositories/ride_repository.dart';
import 'firebase_options.dart';

/// Top-level handler for background/terminated FCM messages.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Navigate based on the data payload of an FCM message.
void _handleNotificationTap(RemoteMessage message, GoRouter router) {
  final data = message.data;
  final screen = data['screen'] as String?;
  final rideId = data['rideId'] as String?;
  final chatId = data['chatId'] as String?;

  switch (screen) {
    case 'chat':
      if (chatId != null) {
        router.push(AppRoutes.chat, extra: {
          'chatId': chatId,
          'otherUserName': 'Chat',
        });
      }
    case 'driverProfile':
      if (rideId != null) {
        router.push(AppRoutes.driverProfile, extra: {'rideId': rideId});
      }
    case 'rideRequests':
      if (rideId != null) {
        router.push('/ride-requests/$rideId');
      }
    default:
      router.push(AppRoutes.home);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  final token = await messaging.getToken();
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (token != null && uid != null) {
    await RideRepository().saveFcmToken(uid, token);
  }

  messaging.onTokenRefresh.listen((newToken) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null) {
      RideRepository().saveFcmToken(currentUid, newToken);
    }
  });

  runApp(const ProviderScope(child: UniPoolApp()));
}

class UniPoolApp extends ConsumerWidget {
  const UniPoolApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'UniPool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF004952),
        useMaterial3: true,
      ),
      routerConfig: router,
      builder: (context, child) => _NotificationHandler(child: child!),
    );
  }
}

/// Handles FCM taps AND watches the passenger's active ride globally.
/// When the ride flips to 'completed', the rating screen is pushed
/// regardless of which screen the passenger is currently on.
class _NotificationHandler extends ConsumerStatefulWidget {
  final Widget child;
  const _NotificationHandler({required this.child});

  @override
  ConsumerState<_NotificationHandler> createState() =>
      _NotificationHandlerState();
}

class _NotificationHandlerState extends ConsumerState<_NotificationHandler> {
  StreamSubscription<QuerySnapshot>? _rideWatcher;

  // Track which rideIds we've already shown the rating for so we
  // don't push it twice (e.g. stream emits multiple times).
  final Set<String> _ratedRideIds = {};

  @override
  void initState() {
    super.initState();
    _setupFcmHandlers();
    _setupPassengerRideWatcher();
  }

  @override
  void dispose() {
    _rideWatcher?.cancel();
    super.dispose();
  }

  // ── FCM handlers ─────────────────────────────────────────────────────────

  void _setupFcmHandlers() {
    final router = ref.read(routerProvider);

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationTap(message, router);
    });

    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _handleNotificationTap(message, router);
        });
      }
    });
  }

  // ── Global passenger ride-completion watcher ──────────────────────────────

  void _setupPassengerRideWatcher() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Listen to all rides where this user is a passenger and status is active.
    // When one flips to 'completed', push the rating screen.
    _rideWatcher = FirebaseFirestore.instance
        .collection('rides')
        .where('passengerIds', arrayContains: uid)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .listen((snap) async {
      for (final doc in snap.docs) {
        final rideId = doc.id;

        // Already shown rating for this ride — skip
        if (_ratedRideIds.contains(rideId)) continue;

        // Check if passenger has already submitted a rating for this ride
        final existingRating = await FirebaseFirestore.instance
            .collection('ratings')
            .doc('${rideId}_$uid')
            .get();

        if (existingRating.exists) {
          _ratedRideIds.add(rideId);
          continue;
        }

        // Mark it so we don't push again on the next stream event
        _ratedRideIds.add(rideId);

        // Fetch driver name
        final data = doc.data();
        final driverId = data['driverId'] as String? ?? '';
        String driverName = 'Driver';
        if (driverId.isNotEmpty) {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(driverId)
                .get();
            driverName = userDoc.data()?['name'] as String? ?? 'Driver';
          } catch (_) {}
        }

        // Push rating screen — slight delay so the router is settled
        if (mounted) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) {
            ref.read(routerProvider).push(
              AppRoutes.rating,
              extra: {
                'rideId': rideId,
                'toUid': driverId,
                'toName': driverName,
                'role': 'passenger', // passenger rating the driver
              },
            );
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
