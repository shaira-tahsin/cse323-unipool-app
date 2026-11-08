import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../data/models/ride_model.dart';
import '../../../data/repositories/ride_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/ride_provider.dart';
import '../../widgets/primary_button.dart';

// ── Provider: search results ──────────────────────────────────────────────

final _rideSearchProvider = FutureProvider.family<List<RideModel>, _SearchParams>(
  (ref, params) async {
    final repo = ref.read(rideRepositoryProvider);
    return repo.searchRides(
      universityDomain: params.universityDomain,
      fromLat: params.fromLat,
      fromLng: params.fromLng,
      toLat: params.toLat,
      toLng: params.toLng,
      excludeUid: params.excludeUid,
      departureTime: params.departureTime, // ← new
    );
  },
);

class _SearchParams {
  final String universityDomain;
  final double fromLat;
  final double fromLng;
  final double toLat;
  final double toLng;
  final String? excludeUid;
  final DateTime? departureTime; // ← new

  const _SearchParams({
    required this.universityDomain,
    required this.fromLat,
    required this.fromLng,
    required this.toLat,
    required this.toLng,
    this.excludeUid,
    this.departureTime,
  });

  @override
  bool operator ==(Object other) =>
      other is _SearchParams &&
      other.universityDomain == universityDomain &&
      other.fromLat == fromLat &&
      other.fromLng == fromLng &&
      other.toLat == toLat &&
      other.toLng == toLng &&
      other.excludeUid == excludeUid &&
      other.departureTime == departureTime;

  @override
  int get hashCode => Object.hash(
      universityDomain, fromLat, fromLng, toLat, toLng, excludeUid, departureTime);
}

// ── Screen ────────────────────────────────────────────────────────────────

class RideResultsScreen extends ConsumerWidget {
  final String fromName;
  final String toName;
  final double? fromLat;
  final double? fromLng;
  final double? toLat;
  final double? toLng;
  final DateTime? departureTime; // ← new

  const RideResultsScreen({
    super.key,
    required this.fromName,
    required this.toName,
    this.fromLat,
    this.fromLng,
    this.toLat,
    this.toLng,
    this.departureTime,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProfileProvider).valueOrNull;

    if (toLat == null || toLng == null || user == null) {
      return _scaffold(
        context,
        child: const Center(
          child: Text('No rides found.',
              style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }

    final params = _SearchParams(
      universityDomain: user.universityDomain,
      fromLat: fromLat ?? 0.0,
      fromLng: fromLng ?? 0.0,
      toLat: toLat!,
      toLng: toLng!,
      excludeUid: user.uid,
      departureTime: departureTime, // ← new
    );

    final resultsAsync = ref.watch(_rideSearchProvider(params));

    return _scaffold(
      context,
      child: resultsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.textMuted, size: 48),
              const SizedBox(height: 12),
              const Text('Something went wrong.',
                  style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(_rideSearchProvider(params)),
                child: const Text('Retry',
                    style: TextStyle(color: AppColors.primaryMid)),
              ),
            ],
          ),
        ),
        data: (rides) {
          if (rides.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_car_outlined,
                      size: 64,
                      color: AppColors.primaryLight.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  const Text(
                    'No rides found',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Try a different time or destination.',
                    style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            itemCount: rides.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _RideCard(ride: rides[i]),
          );
        },
      ),
    );
  }

  Widget _scaffold(BuildContext context, {required Widget child}) {
    final timeStr = departureTime != null
        ? DateFormat('MMM d  •  h:mm a').format(departureTime!)
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      size: 20, color: AppColors.dark),
                ),
                const SizedBox(height: 16),
                const Text(
                  'We found rides matching\nyour destination',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                if (toName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: AppColors.primaryMid),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          toName,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                // ── Show selected time ──────────────────────────────────
                if (timeStr != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded,
                          size: 14, color: AppColors.primaryMid),
                      const SizedBox(width: 4),
                      Text(
                        '$timeStr  ±10 min',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.surface),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ── Ride card ─────────────────────────────────────────────────────────────

class _RideCard extends StatelessWidget {
  final RideModel ride;

  const _RideCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    final depTime = ride.departureTime.toDate();
    final timeStr = DateFormat('h:mm a').format(depTime);
    final dateStr = DateFormat('MMM d').format(depTime);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.1),
                border: Border.all(
                    color: AppColors.primaryLight.withOpacity(0.4), width: 1.5),
              ),
              child: const Icon(Icons.person, color: AppColors.primary, size: 28),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        ride.driverName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Tk. ${ride.fare}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$dateStr  •  $timeStr',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ride.licencePlate,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 13, color: AppColors.primaryMid),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          ride.toLocation.name,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton(
                      onPressed: () {
                        context.push(
                          AppRoutes.driverProfile,
                          extra: {'rideId': ride.id},
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Join Ride',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
