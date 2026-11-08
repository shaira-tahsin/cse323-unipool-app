import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/ride_provider.dart';
import '../../widgets/ride_card.dart';
import '../notifications/notifications_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(authStateProvider);
    final user = userAsync.valueOrNull;
    final uid = user?.uid ?? '';
    final displayName = user?.displayName?.split(' ').first ?? 'there';

    final ridesAsync = ref.watch(upcomingRidesProvider(uid));
    final unread = ref.watch(unreadNotificationsProvider).valueOrNull ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                // ── Greeting ───────────────────────────────────────────
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Row(
                        children: [
                          // Profile avatar
                          GestureDetector(
                            onTap: () => context.push(AppRoutes.profile),
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary.withValues(alpha: 0.12),
                                border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: user?.photoURL != null
                                  ? ClipOval(
                                      child: Image.network(
                                        user!.photoURL!,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.person,
                                      color: AppColors.primary,
                                      size: 22,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Hello $displayName!',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const Spacer(),

                          // ── Three-dot menu with unread badge ──────────
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert_rounded,
                                    color: AppColors.textMuted, size: 22),
                                color: AppColors.white,
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                onSelected: (value) async {
                                  if (value == 'history') {
                                    context.push(AppRoutes.rideHistory);
                                  } else if (value == 'notifications') {
                                    context.push(AppRoutes.notifications);
                                  } else if (value == 'logout') {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Log out?'),
                                        content: const Text(
                                            'You will be returned to the login screen.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(true),
                                            child: const Text('Log out',
                                                style: TextStyle(
                                                    color: AppColors.primary)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      ref
                                          .read(authNotifierProvider.notifier)
                                          .signOut();
                                    }
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'history',
                                    child: Row(
                                      children: [
                                        Icon(Icons.history_rounded,
                                            color: AppColors.primary, size: 20),
                                        SizedBox(width: 12),
                                        Text('Ride History',
                                            style: TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 14)),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'notifications',
                                    child: Row(
                                      children: [
                                        Icon(Icons.notifications_outlined,
                                            color: AppColors.primary, size: 20),
                                        SizedBox(width: 12),
                                        Text('Notifications',
                                            style: TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 14)),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem(
                                    value: 'logout',
                                    child: Row(
                                      children: [
                                        Icon(Icons.logout_rounded,
                                            color: Colors.red, size: 20),
                                        SizedBox(width: 12),
                                        Text('Log out',
                                            style: TextStyle(
                                                color: Colors.red,
                                                fontSize: 14)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (unread > 0)
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Section title ───────────────────────────────────────
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 28, 20, 14),
                    child: Text(
                      'Your Rides',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),

                // ── Rides list ──────────────────────────────────────────
                ridesAsync.when(
                  loading: () => const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2.5,
                        ),
                      ),
                    ),
                  ),
                  error: (e, _) => const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Could not load rides.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  data: (rides) {
                    if (rides.isEmpty) {
                      return SliverToBoxAdapter(child: _EmptyRidesState());
                    }
                    final shown = rides.take(3).toList();
                    final hasMore = rides.length > 3;

                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index < shown.length) {
                            final ride = shown[index];
                            final role =
                                ride.driverId == uid ? 'driver' : 'passenger';
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: RideCard(ride: ride, role: role),
                            );
                          } else {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 4),
                              child: GestureDetector(
                                onTap: () =>
                                    context.push(AppRoutes.rideHistory),
                                child: const Center(
                                  child: Text(
                                    'Show more',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textMuted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                        childCount: shown.length + (hasMore ? 1 : 0),
                      ),
                    );
                  },
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),

          // ── Bottom action panel ─────────────────────────────────────
          _BottomActionPanel(),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyRidesState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.directions_car_outlined,
            size: 56,
            color: AppColors.primaryLight.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          const Text(
            'No upcoming rides',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Offer or join a ride to get started.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ── Bottom action panel ───────────────────────────────────────────────────────

class _BottomActionPanel extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        28,
        24,
        MediaQuery.of(context).padding.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'What do you want to do?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () => context.push(AppRoutes.offerRide),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryMid,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Offer Ride',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'or',
            style: TextStyle(fontSize: 13, color: AppColors.primaryLight),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () => context.push(AppRoutes.joinRide),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Join Ride',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
