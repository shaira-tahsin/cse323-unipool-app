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

// ── Provider: fetch single ride ───────────────────────────────────────────

final _singleRideProvider =
    FutureProvider.family<RideModel?, String>((ref, rideId) async {
  final repo = ref.read(rideRepositoryProvider);
  return repo.getRide(rideId);
});

// ── Screen ────────────────────────────────────────────────────────────────

class DriverProfileScreen extends ConsumerWidget {
  final String rideId;

  const DriverProfileScreen({super.key, required this.rideId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rideAsync = ref.watch(_singleRideProvider(rideId));
    final currentUser = ref.watch(userProfileProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: rideAsync.when(
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
              const Text('Could not load ride details.',
                  style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(_singleRideProvider(rideId)),
                child: const Text('Retry',
                    style: TextStyle(color: AppColors.primaryMid)),
              ),
            ],
          ),
        ),
        data: (ride) {
          if (ride == null) {
            return const Center(
              child: Text('Ride not found.',
                  style: TextStyle(color: AppColors.textMuted)),
            );
          }

          if (currentUser == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final statusAsync = ref.watch(requestStatusStreamProvider(
            (rideId: ride.id, passengerId: currentUser.uid),
          ));

          final requestStatus = statusAsync.valueOrNull;
          final hasRequested = requestStatus != null;

          return _DriverProfileBody(
            ride: ride,
            passengerId: currentUser.uid,
            requestStatus: requestStatus,
            hasRequested: hasRequested,
          );
        },
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────

class _DriverProfileBody extends ConsumerWidget {
  final RideModel ride;
  final String passengerId;
  final String? requestStatus;
  final bool hasRequested;

  const _DriverProfileBody({
    required this.ride,
    required this.passengerId,
    required this.requestStatus,
    required this.hasRequested,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final depTime = ride.departureTime.toDate();
    final timeStr = DateFormat('h:mm a').format(depTime);
    final dateStr = DateFormat('MMM d, yyyy').format(depTime);

    final joinState = ref.watch(joinRequestProvider);
    final isAccepted = requestStatus == 'accepted';
    final isRejected = requestStatus == 'rejected';
    final isPending = requestStatus == 'pending';

    // If accepted or pending, back button goes home (ride is now on home screen)
    // If pre-join or rejected, back button pops normally
    void handleBack() {
      if (isAccepted || isPending) {
        context.go(AppRoutes.home);
      } else {
        Navigator.of(context).pop();
      }
    }

    final String headline;
    if (!hasRequested) {
      headline = "Join ${ride.driverName.split(' ').first}'s ride";
    } else if (isPending) {
      headline = 'Request sent!\nWaiting for ${ride.driverName.split(' ').first}…';
    } else if (isAccepted) {
      headline = "You're in! ${ride.driverName.split(' ').first} accepted your request.";
    } else if (isRejected) {
      headline = 'Your request was declined.';
    } else {
      headline = "Join ${ride.driverName.split(' ').first}'s ride";
    }

    return PopScope(
      // Intercept Android back gesture/button
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) handleBack();
      },
      child: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: handleBack,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 16, color: AppColors.dark),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Headline
                    Text(
                      headline,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isRejected
                            ? Colors.redAccent
                            : AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),

                    // Pending status chip
                    if (isPending) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryMid,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Awaiting driver response…',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.primaryMid,
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Accepted status chip
                    if (isAccepted) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: const [
                          Icon(Icons.check_circle_rounded,
                              color: Colors.green, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Ride confirmed',
                            style: TextStyle(
                                fontSize: 13, color: Colors.green),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 32),

                    // Avatar + name + licence
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary.withOpacity(0.12),
                              border: Border.all(
                                  color: AppColors.primaryMid, width: 2),
                            ),
                            child: const Icon(Icons.person_rounded,
                                size: 44, color: AppColors.primary),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            ride.driverName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'License number: ${ride.licencePlate}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Details table
                    const Divider(color: AppColors.surface),
                    _DetailRow(
                        label: 'Leaves at',
                        value: '$dateStr  •  $timeStr'),
                    const Divider(color: AppColors.surface),
                    _DetailRow(
                        label: 'Fare', value: 'Tk. ${ride.fare}'),
                    const Divider(color: AppColors.surface),
                    _DetailRow(
                      label: 'Seats left',
                      value:
                          '${ride.availableSeats - ride.passengerIds.length} / ${ride.availableSeats}',
                    ),
                    const Divider(color: AppColors.surface),
                    const SizedBox(height: 8),

                    // Route summary
                    _RouteRow(
                      fromName: ride.fromLocation.name,
                      toName: ride.toLocation.name,
                    ),

                    const SizedBox(height: 36),

                    // ── Primary action button ────────────────────────────
                    if (!hasRequested) ...[
                      // PRE-JOIN: Confirm Join
                      PrimaryButton(
                        label: 'Confirm Join',
                        backgroundColor: AppColors.primary,
                        isLoading: joinState.isLoading,
                        onPressed: joinState.isLoading
                            ? null
                            : () async {
                                await ref
                                    .read(joinRequestProvider.notifier)
                                    .sendRequest(ride.id, passengerId);

                                if (!context.mounted) return;

                                final result = ref.read(joinRequestProvider);
                                if (result.hasError) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Failed to send request. Please try again.'),
                                    ),
                                  );
                                }
                              },
                      ),
                      const SizedBox(height: 12),

                      // Disabled "Chat with Driver" in pre-join
                      PrimaryButton(
                        label:
                            'Chat with ${ride.driverName.split(' ').first}',
                        backgroundColor: AppColors.surface,
                        textColor: AppColors.textMuted,
                        onPressed: null,
                      ),
                    ] else if (isRejected) ...[
                      // REJECTED: go back to results
                      PrimaryButton(
                        label: 'Find another ride',
                        backgroundColor: AppColors.primary,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ] else ...[
                      // POST-JOIN (pending or accepted):
                      PrimaryButton(
                        label:
                            'Chat with ${ride.driverName.split(' ').first}',
                        backgroundColor: isAccepted
                            ? AppColors.primary
                            : AppColors.surface,
                        textColor: isAccepted
                            ? AppColors.white
                            : AppColors.textMuted,
                        onPressed: isAccepted
                            ? () {
                                context.push(
                                  AppRoutes.chat,
                                  extra: {
                                    'chatId':
                                        '${ride.id}_$passengerId',
                                    'otherUserName': ride.driverName,
                                  },
                                );
                              }
                            : null,
                      ),
                    ],

                    if (joinState.hasError) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Error: ${joinState.error}',
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detail row ────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textMuted)),
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

// ── Route summary ─────────────────────────────────────────────────────────

class _RouteRow extends StatelessWidget {
  final String fromName;
  final String toName;

  const _RouteRow({required this.fromName, required this.toName});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primaryMid, width: 2),
              ),
            ),
            Container(
              width: 2,
              height: 30,
              color: AppColors.primaryLight.withOpacity(0.5),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryMid,
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fromName,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              Text(
                toName,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
