import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../data/models/ride_model.dart';
import '../../../providers/ride_provider.dart';
import '../../widgets/primary_button.dart';

class ActiveRideScreen extends ConsumerStatefulWidget {
  final String rideId;

  const ActiveRideScreen({super.key, required this.rideId});

  @override
  ConsumerState<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends ConsumerState<ActiveRideScreen> {
  StreamSubscription<Position>? _gpsSub;
  bool _locationPermissionDenied = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    super.dispose();
  }

  // ── GPS tracking ──────────────────────────────────────────────────────────

  Future<void> _startLocationTracking() async {
    // Check / request permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _locationPermissionDenied = true);
      return;
    }

    // Stream GPS every 10 seconds or 50 metres, whichever comes first
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((position) {
      ref.read(driverLocationProvider.notifier).update(
            widget.rideId,
            position.latitude,
            position.longitude,
          );
    });
  }

  // ── Cancel ride ───────────────────────────────────────────────────────────

  Future<void> _cancelRide(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel ride?'),
        content: const Text(
            'This will cancel the ride for all passengers. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep ride'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel ride',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    await ref.read(rideRepositoryProvider).cancelRide(widget.rideId);
    if (context.mounted) context.go(AppRoutes.home);
  }

  // ── Start ride ────────────────────────────────────────────────────────────

  Future<void> _startRide(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start ride?'),
        content: const Text(
            'This will notify passengers that the ride has started.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not yet'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Start',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    await ref.read(rideRepositoryProvider).startRide(widget.rideId);
  }

  // ── Complete ride ─────────────────────────────────────────────────────────

  Future<void> _completeRide(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete ride?'),
        content: const Text('Mark this ride as completed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not yet'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Complete',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    // Fetch passenger list before marking complete
    final rideDoc =
        await _firestore.collection('rides').doc(widget.rideId).get();
    final passengerIds =
        List<String>.from(rideDoc.data()?['passengerIds'] as List? ?? []);

    await _firestore.collection('rides').doc(widget.rideId).update({
      'status': 'completed',
    });

    if (!context.mounted) return;

    // Push a rating screen for each passenger one at a time
    for (final passengerId in passengerIds) {
      if (!context.mounted) break;
      final name = await ref
          .read(rideRepositoryProvider)
          .getUserName(passengerId);
      if (!context.mounted) break;
      await context.push(AppRoutes.rating, extra: {
        'rideId': widget.rideId,
        'toUid': passengerId,
        'toName': name,
        'role': 'driver',
      });
    }

    if (context.mounted) context.go(AppRoutes.home);
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: AppColors.primary,
      statusBarIconBrightness: Brightness.light,
    ));
    final rideAsync = ref.watch(rideStreamProvider(widget.rideId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: rideAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Text('Error: $e',
              style: const TextStyle(color: AppColors.textMuted)),
        ),
        data: (ride) {
          if (ride == null) {
            return const Center(
              child: Text('Ride not found.',
                  style: TextStyle(color: AppColors.textMuted)),
            );
          }
          return _RideBody(
            ride: ride,
            locationPermissionDenied: _locationPermissionDenied,
            onStart: () => _startRide(context),
            onCancel: () => _cancelRide(context),
            onComplete: () => _completeRide(context),
            onOpenChat: (passengerId, passengerName) {
              final chatId = _chatId(ride.driverId, passengerId);
              context.push(AppRoutes.chat, extra: {
                'chatId': chatId,
                'otherUserName': passengerName,
              });
            },
          );
        },
      ),
    );
  }

  /// Deterministic chat ID — same for both sides of the conversation.
  String _chatId(String driverId, String passengerId) {
    final sorted = [driverId, passengerId]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }
}

// ── Body widget ───────────────────────────────────────────────────────────────

class _RideBody extends StatelessWidget {
  final RideModel ride;
  final bool locationPermissionDenied;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onComplete;
  final void Function(String passengerId, String passengerName) onOpenChat;

  const _RideBody({
    required this.ride,
    required this.locationPermissionDenied,
    required this.onStart,
    required this.onCancel,
    required this.onComplete,
    required this.onOpenChat,
  });

  @override
  Widget build(BuildContext context) {
    final departure =
        DateFormat('h:mm a').format(ride.departureTime.toDate());

    return SafeArea(
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────
          _Header(departure: departure, status: ride.status),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // GPS warning
                  if (locationPermissionDenied) _GpsWarning(),

                  // Route card
                  _RouteCard(ride: ride),
                  const SizedBox(height: 20),

                  // Passengers
                  _PassengersSection(
                    ride: ride,
                    onOpenChat: onOpenChat,
                  ),
                  const SizedBox(height: 28),

                  // Actions
                  if (ride.status == 'active') ...[
                    PrimaryButton(
                      label: 'Complete Ride',
                      onPressed: onComplete,
                      backgroundColor: AppColors.primary,
                    ),
                  ] else ...[
                    PrimaryButton(
                      label: 'Start Ride',
                      onPressed: onStart,
                      backgroundColor: AppColors.primaryMid,
                    ),
                  ],
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: 'Cancel Ride',
                    onPressed: onCancel,
                    isOutlined: true,
                    textColor: Colors.red,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String departure;
  final String status;

  const _Header({required this.departure, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: const Icon(Icons.arrow_back_ios_new,
                    color: AppColors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Active Ride',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                ),
              ),
              const Spacer(),
              // Status / Live indicator
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: status == 'active'
                      ? Colors.greenAccent.withOpacity(0.2)
                      : Colors.orangeAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: status == 'active'
                        ? Colors.greenAccent.shade400
                        : Colors.orangeAccent.shade400,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: status == 'active'
                            ? Colors.greenAccent.shade400
                            : Colors.orangeAccent.shade400,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      status == 'active' ? 'Live' : 'Not started',
                      style: TextStyle(
                        fontSize: 12,
                        color: status == 'active'
                            ? Colors.greenAccent.shade400
                            : Colors.orangeAccent.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Departing at $departure',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.primaryLight,
            ),
          ),
        ],
      ),
    );
  }
}

// ── GPS warning ───────────────────────────────────────────────────────────────

class _GpsWarning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.location_off_rounded,
              color: Colors.orange.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Location permission denied. Passengers cannot see your live location.',
              style: TextStyle(
                  fontSize: 13, color: Colors.orange.shade800),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Route card ────────────────────────────────────────────────────────────────

class _RouteCard extends StatelessWidget {
  final RideModel ride;

  const _RouteCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _RouteRow(
            icon: Icons.radio_button_checked,
            color: AppColors.primaryMid,
            label: 'From',
            value: ride.fromLocation.name,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 11),
            child: Row(
              children: [
                Container(
                  width: 1.5,
                  height: 24,
                  color: AppColors.primaryLight.withOpacity(0.5),
                ),
              ],
            ),
          ),
          _RouteRow(
            icon: Icons.location_on,
            color: AppColors.primary,
            label: 'To',
            value: ride.toLocation.name,
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _InfoChip(
                icon: Icons.people_outline,
                label: '${ride.passengerIds.length} passenger(s)',
              ),
              _InfoChip(
                icon: Icons.monetization_on_outlined,
                label: 'Tk. ${ride.fare}',
              ),
              _InfoChip(
                icon: Icons.directions_car_outlined,
                label: ride.licencePlate,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _RouteRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted)),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.primaryMid),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textMuted)),
      ],
    );
  }
}

// ── Passengers section ────────────────────────────────────────────────────────

class _PassengersSection extends StatelessWidget {
  final RideModel ride;
  final void Function(String passengerId, String passengerName) onOpenChat;

  const _PassengersSection({
    required this.ride,
    required this.onOpenChat,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Passengers',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        if (ride.passengerIds.isEmpty)
          const Text(
            'No passengers yet.',
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          )
        else
          ...ride.passengerIds.map(
            (uid) => _PassengerTile(
              passengerId: uid,
              onChat: (name) => onOpenChat(uid, name),
            ),
          ),
      ],
    );
  }
}

// ── Passenger tile ────────────────────────────────────────────────────────────
// Fetches the passenger's name from Firestore once, then shows a chat button.

class _PassengerTile extends ConsumerWidget {
  final String passengerId;
  final void Function(String name) onChat;

  const _PassengerTile({
    required this.passengerId,
    required this.onChat,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lightweight fetch of passenger display name from /users/{uid}
    final nameAsync = ref.watch(_passengerNameProvider(passengerId));

    final name = nameAsync.valueOrNull ?? 'Passenger';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            child: const Icon(Icons.person,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => onChat(name),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.chat_bubble_outline,
                      color: AppColors.white, size: 14),
                  SizedBox(width: 5),
                  Text(
                    'Chat',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Fetches a passenger's display name from /users/{uid}.
// Uses getUserName() which we add to RideRepository in this step.
final _passengerNameProvider =
    FutureProvider.family<String, String>((ref, uid) async {
  return ref.read(rideRepositoryProvider).getUserName(uid);
});
