import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/ride_provider.dart';

class RideRequestsScreen extends ConsumerWidget {
  final String rideId;

  const RideRequestsScreen({super.key, required this.rideId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(joinRequestsStreamProvider(rideId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Ride Requests',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: requestsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Text(
            'Something went wrong.\n$e',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
        data: (requests) {
          if (requests.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined, size: 56, color: AppColors.primaryLight),
                  SizedBox(height: 16),
                  Text(
                    'No pending requests',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final request = requests[index];
              final passengerId = request['passengerId'] as String? ?? request['id'] as String;

              return _RequestCard(
                rideId: rideId,
                passengerId: passengerId,
                createdAt: request['createdAt'] as Timestamp?,
              );
            },
          );
        },
      ),
    );
  }
}

// ── Individual request card ───────────────────────────────────────────────

class _RequestCard extends ConsumerWidget {
  final String rideId;
  final String passengerId;
  final Timestamp? createdAt;

  const _RequestCard({
    required this.rideId,
    required this.passengerId,
    this.createdAt,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionState = ref.watch(rideRequestActionProvider);
    final isLoading = actionState is AsyncLoading;

    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchPassengerData(passengerId),
      builder: (context, snapshot) {
        final name = snapshot.data?['name'] as String? ?? 'Loading…';
        final phone = snapshot.data?['phone'] as String? ?? '';
        final hasData = snapshot.connectionState == ConnectionState.done;

        return Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.primary,
                child: Text(
                  hasData && name != 'Loading…'
                      ? name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Name + phone
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        phone,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                    if (createdAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(createdAt!),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Accept / Reject buttons
              if (isLoading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Reject button
                    _ActionButton(
                      icon: Icons.close,
                      color: Colors.red.shade400,
                      tooltip: 'Reject',
                      onTap: () => _handleReject(context, ref),
                    ),
                    const SizedBox(width: 8),
                    // Accept button
                    _ActionButton(
                      icon: Icons.check,
                      color: AppColors.primaryMid,
                      tooltip: 'Accept',
                      onTap: () => _handleAccept(context, ref),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleAccept(BuildContext context, WidgetRef ref) async {
    await ref
        .read(rideRequestActionProvider.notifier)
        .accept(rideId, passengerId);

    final state = ref.read(rideRequestActionProvider);
    if (state is AsyncError && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to accept: ${state.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleReject(BuildContext context, WidgetRef ref) async {
    await ref
        .read(rideRequestActionProvider.notifier)
        .reject(rideId, passengerId);

    final state = ref.read(rideRequestActionProvider);
    if (state is AsyncError && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to reject: ${state.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Map<String, dynamic>?> _fetchPassengerData(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!doc.exists) return null;
    return doc.data();
  }

  String _formatTime(Timestamp ts) {
    final dt = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}';
  }
}

// ── Small icon action button ──────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}
