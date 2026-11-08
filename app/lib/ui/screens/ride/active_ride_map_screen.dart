import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../data/models/ride_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/ride_provider.dart';

class ActiveRideMapScreen extends ConsumerStatefulWidget {
  final String rideId;

  const ActiveRideMapScreen({super.key, required this.rideId});

  @override
  ConsumerState<ActiveRideMapScreen> createState() =>
      _ActiveRideMapScreenState();
}

class _ActiveRideMapScreenState extends ConsumerState<ActiveRideMapScreen> {
  GoogleMapController? _mapController;

  // Markers shown on the map
  final Map<String, Marker> _markers = {};

  // Tracks the last known driver LatLng so we only animate camera on change
  LatLng? _lastDriverLatLng;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  // ── Map helpers ───────────────────────────────────────────────────────────

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // Once the map is ready, immediately jump to driver if location already exists
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_lastDriverLatLng != null) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(_lastDriverLatLng!, 15),
        );
      }
    });
  }

  /// Rebuilds the marker set from the latest ride snapshot.
  void _updateMarkers(RideModel ride) {
    final markers = <String, Marker>{};

    // Destination marker
    markers['destination'] = Marker(
      markerId: const MarkerId('destination'),
      position: LatLng(
        ride.toLocation.lat,
        ride.toLocation.lng,
      ),
      infoWindow: InfoWindow(title: ride.toLocation.name),
      icon: BitmapDescriptor.defaultMarkerWithHue(180.0), // teal
    );

    // Driver marker (only if driverLocation is present in the doc)
    final driverLoc = ride.driverLocation;
    if (driverLoc != null) {
      final driverLatLng = LatLng(driverLoc['lat']!, driverLoc['lng']!);
      markers['driver'] = Marker(
        markerId: const MarkerId('driver'),
        position: driverLatLng,
        infoWindow: InfoWindow(title: ride.driverName),
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      );

      // Always store the latest position so _onMapCreated can use it
      _lastDriverLatLng = driverLatLng;

      // Animate camera to driver every time their position updates
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(driverLatLng, 15),
      );
    }

    setState(() => _markers
      ..clear()
      ..addAll(markers));
  }

  // ── Chat helper ───────────────────────────────────────────────────────────

  String _chatId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rideAsync = ref.watch(rideStreamProvider(widget.rideId));

    return Scaffold(
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

          // Side-effect: update markers whenever ride data changes
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _updateMarkers(ride),
          );

          // If ride is cancelled or completed, show an overlay
          final isEnded =
              ride.status == 'cancelled' || ride.status == 'completed';

          return Stack(
            children: [
              // ── Map ────────────────────────────────────────────────
              GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: CameraPosition(
                  target: LatLng(
                    ride.fromLocation.lat,
                    ride.fromLocation.lng,
                  ),
                  zoom: 14,
                ),
                markers: Set<Marker>.of(_markers.values),
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),

              // ── Top bar ────────────────────────────────────────────
              SafeArea(
                child: _TopBar(
                  driverName: ride.driverName,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
              ),

              // ── Bottom info sheet ──────────────────────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _BottomSheet(
                  ride: ride,
                  onChat: (currentUid) {
                    final chatId = _chatId(currentUid, ride.driverId);
                    context.push(AppRoutes.chat, extra: {
                      'chatId': chatId,
                      'otherUserName': ride.driverName,
                    });
                  },
                ),
              ),

              // ── Ride ended overlay ─────────────────────────────────
              if (isEnded)
                _RideEndedOverlay(
                  status: ride.status,
                  rideId: widget.rideId,
                  driverId: ride.driverId,
                  driverName: ride.driverName,
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String driverName;
  final VoidCallback onBack;

  const _TopBar({required this.driverName, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  color: AppColors.primary, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          // Driver label
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.directions_car,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 6),
                Text(
                  driverName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Live indicator
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.shade400,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Live',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.greenAccent.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom sheet ──────────────────────────────────────────────────────────────

class _BottomSheet extends ConsumerWidget {
  final RideModel ride;
  final void Function(String currentUid) onChat;

  const _BottomSheet({required this.ride, required this.onChat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departure =
        DateFormat('h:mm a').format(ride.departureTime.toDate());

    // Get current user uid for chat ID generation
    final userAsync = ref.watch(authStateProvider);
    final currentUid = userAsync.valueOrNull?.uid ?? '';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Route summary
          Row(
            children: [
              const Icon(Icons.location_on,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${ride.fromLocation.name} → ${ride.toLocation.name}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Details row
          Row(
            children: [
              _DetailPill(
                icon: Icons.access_time,
                label: departure,
              ),
              const SizedBox(width: 10),
              _DetailPill(
                icon: Icons.monetization_on_outlined,
                label: 'Tk. ${ride.fare}',
              ),
              const SizedBox(width: 10),
              _DetailPill(
                icon: Icons.directions_car_outlined,
                label: ride.licencePlate,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Driver location status
          _DriverLocationStatus(ride: ride),
          const SizedBox(height: 16),

          // Chat button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed:
                  currentUid.isNotEmpty ? () => onChat(currentUid) : null,
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: Text('Chat with ${ride.driverName}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Driver location status ────────────────────────────────────────────────────

class _DriverLocationStatus extends StatelessWidget {
  final RideModel ride;

  const _DriverLocationStatus({required this.ride});

  @override
  Widget build(BuildContext context) {
    final hasLocation = ride.driverLocation != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: hasLocation
            ? Colors.green.shade50
            : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            hasLocation
                ? Icons.location_on
                : Icons.location_searching,
            color: hasLocation
                ? Colors.green.shade600
                : AppColors.textMuted,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            hasLocation
                ? 'Driver location is live on the map'
                : 'Waiting for driver location…',
            style: TextStyle(
              fontSize: 13,
              color: hasLocation
                  ? Colors.green.shade700
                  : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Detail pill ───────────────────────────────────────────────────────────────

class _DetailPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.primaryMid),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

// ── Ride ended overlay ────────────────────────────────────────────────────────

class _RideEndedOverlay extends StatelessWidget {
  final String status;
  final String rideId;
  final String driverId;
  final String driverName;

  const _RideEndedOverlay({
    required this.status,
    required this.rideId,
    required this.driverId,
    required this.driverName,
  });

  @override
  Widget build(BuildContext context) {
    final isCancelled = status == 'cancelled';

    return Container(
      color: Colors.black.withOpacity(0.55),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isCancelled
                    ? Icons.cancel_outlined
                    : Icons.check_circle_outline,
                color: isCancelled ? Colors.red : Colors.green,
                size: 52,
              ),
              const SizedBox(height: 12),
              Text(
                isCancelled ? 'Ride Cancelled' : 'Ride Completed',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isCancelled
                    ? 'The driver has cancelled this ride.'
                    : 'You have arrived at your destination.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    // Passenger rates the driver after completion
                    if (!isCancelled) {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid != null && context.mounted) {
                        await context.push(AppRoutes.rating, extra: {
                          'rideId': rideId,
                          'toUid': driverId,
                          'toName': driverName,
                          'role': 'passenger',
                        });
                      }
                    }
                    if (context.mounted) context.go(AppRoutes.home);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(isCancelled ? 'Back to Home' : 'Rate & Go Home'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
