import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../data/models/ride_model.dart';

class RideCard extends ConsumerWidget {
  final RideModel ride;
  final String role; // 'driver' or 'passenger'
  final VoidCallback? onTap;

  const RideCard({
    super.key,
    required this.ride,
    required this.role,
    this.onTap,
  });

  Future<void> _handleAction(BuildContext context) async {
    final isDriver = role == 'driver';
    final actionLabel = isDriver ? 'Cancel Ride' : 'Leave Ride';
    final message = isDriver
        ? 'Cancel this ride? All passengers will be notified.'
        : 'Leave this ride?';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(actionLabel),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              actionLabel,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      if (isDriver) {
        await FirebaseFirestore.instance
            .collection('rides')
            .doc(ride.id)
            .update({'status': 'cancelled'});
      } else {
        final uid = _getCurrentUid();
        if (uid == null) return;
        await FirebaseFirestore.instance
            .collection('rides')
            .doc(ride.id)
            .update({
          'passengerIds': FieldValue.arrayRemove([uid]),
        });
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Something went wrong. Please try again.')),
        );
      }
    }
  }

  String? _getCurrentUid() => FirebaseAuth.instance.currentUser?.uid;

  // ── Navigation helpers ────────────────────────────────────────────────────

  void _goToActiveRide(BuildContext context) {
    final path =
        AppRoutes.activeRide.replaceFirst(':rideId', ride.id);
    context.push(path);
  }

  void _goToActiveRideMap(BuildContext context) {
    final path =
        AppRoutes.activeRideMap.replaceFirst(':rideId', ride.id);
    context.push(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departureFormatted =
        DateFormat('h:mm a').format(ride.departureTime.toDate());
    final isDriver = role == 'driver';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
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
            // ── Main row ──────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride.toLocation.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          departureFormatted,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ride.licencePlate.isNotEmpty
                              ? ride.licencePlate
                              : 'No plate',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Role badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isDriver ? 'Driver' : 'Passenger',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Action buttons ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  // Cancel / Leave button (always shown)
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: OutlinedButton(
                        onPressed: () => _handleAction(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade600,
                          side: BorderSide(color: Colors.red.shade200),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(
                          isDriver ? 'Cancel Ride' : 'Leave Ride',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  if (isDriver) ...[
                    // Requests button
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: ElevatedButton(
                          onPressed: () {
                            final path = AppRoutes.rideRequests
                                .replaceFirst(':rideId', ride.id);
                            context.push(path);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryMid,
                            foregroundColor: AppColors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text(
                            'Requests',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // NEW — Active Ride button (driver)
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: ElevatedButton(
                          onPressed: () => _goToActiveRide(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text(
                            'Active Ride',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // NEW — Track Ride button (passenger)
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: ElevatedButton.icon(
                          onPressed: () => _goToActiveRideMap(context),
                          icon: const Icon(Icons.location_on, size: 14),
                          label: const Text(
                            'Track Ride',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
