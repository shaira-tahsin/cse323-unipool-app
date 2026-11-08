import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/ride_model.dart';

// ── Providers ──────────────────────────────────────────────────────────────

final _driverHistoryProvider =
    StreamProvider.autoDispose<List<RideModel>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection('rides')
      .where('driverId', isEqualTo: uid)
      .where('status', whereIn: ['completed', 'cancelled'])
      .orderBy('departureTime', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(RideModel.fromDoc).toList());
});

final _passengerHistoryProvider =
    StreamProvider.autoDispose<List<RideModel>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection('rides')
      .where('passengerIds', arrayContains: uid)
      .where('status', whereIn: ['completed', 'cancelled'])
      .orderBy('departureTime', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(RideModel.fromDoc).toList());
});

// ── Screen ─────────────────────────────────────────────────────────────────

class RideHistoryScreen extends ConsumerWidget {
  const RideHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios,
                color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(
            'Ride History',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          bottom: const TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textMuted,
            indicatorColor: AppColors.primaryMid,
            indicatorWeight: 2.5,
            labelStyle:
                TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            tabs: [
              Tab(text: 'As Driver'),
              Tab(text: 'As Passenger'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _HistoryTab(provider: _driverHistoryProvider, role: 'driver'),
            _HistoryTab(
                provider: _passengerHistoryProvider, role: 'passenger'),
          ],
        ),
      ),
    );
  }
}

// ── Tab content ─────────────────────────────────────────────────────────────

class _HistoryTab extends ConsumerWidget {
  final ProviderBase<AsyncValue<List<RideModel>>> provider;
  final String role; // 'driver' | 'passenger'

  const _HistoryTab({required this.provider, required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);

    return async.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primaryMid),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (rides) {
        if (rides.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  role == 'driver'
                      ? Icons.directions_car_outlined
                      : Icons.person_outline,
                  size: 56,
                  color: AppColors.primaryLight,
                ),
                const SizedBox(height: 16),
                Text(
                  role == 'driver'
                      ? 'No rides offered yet'
                      : 'No rides taken yet',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          itemCount: rides.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) =>
              _RideHistoryCard(ride: rides[i], role: role),
        );
      },
    );
  }
}

// ── Card ────────────────────────────────────────────────────────────────────

class _RideHistoryCard extends StatelessWidget {
  final RideModel ride;
  final String role;

  const _RideHistoryCard({required this.ride, required this.role});

  @override
  Widget build(BuildContext context) {
    final dt = ride.departureTime.toDate();
    final dateStr = DateFormat('d MMM y').format(dt);
    final timeStr = DateFormat('h:mm a').format(dt);
    final isCompleted = ride.status == 'completed';

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
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon column
          Column(
            children: [
              const Icon(Icons.radio_button_checked,
                  color: AppColors.primaryMid, size: 18),
              Container(
                width: 2,
                height: 28,
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: AppColors.primaryLight,
              ),
              const Icon(Icons.location_on,
                  color: AppColors.primary, size: 18),
            ],
          ),
          const SizedBox(width: 12),

          // Route + meta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ride.fromLocation.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                Text(
                  ride.toLocation.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                // Date, time, fare row
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      '$dateStr · $timeStr',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.monetization_on_outlined,
                        size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      'Tk. ${ride.fare}',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                    if (role == 'driver') ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.people_outline,
                          size: 12, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        '${ride.passengerIds.length} passenger${ride.passengerIds.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Status badge
          _StatusBadge(isCompleted: isCompleted),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isCompleted;

  const _StatusBadge({required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isCompleted
            ? AppColors.primaryMid.withOpacity(0.12)
            : Colors.red.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isCompleted ? 'Completed' : 'Cancelled',
        style: TextStyle(
          color: isCompleted ? AppColors.primaryMid : Colors.red,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
