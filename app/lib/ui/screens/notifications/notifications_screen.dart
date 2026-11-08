import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';

// ── Model ───────────────────────────────────────────────────────────────────

class NotificationItem {
  final String id;
  final String title;
  final String body;
  final String? screen;
  final String? rideId;
  final String? chatId;
  final bool read;
  final DateTime createdAt;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    this.screen,
    this.rideId,
    this.chatId,
    required this.read,
    required this.createdAt,
  });

  factory NotificationItem.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationItem(
      id: doc.id,
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      screen: data['screen'] as String?,
      rideId: data['rideId'] as String?,
      chatId: data['chatId'] as String?,
      read: data['read'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

// ── Provider ────────────────────────────────────────────────────────────────

final notificationsProvider =
    StreamProvider.autoDispose<List<NotificationItem>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection('notifications')
      .doc(uid)
      .collection('items')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs.map(NotificationItem.fromDoc).toList());
});

// Counts unread notifications — used for badge on home screen dropdown
final unreadNotificationsProvider =
    StreamProvider.autoDispose<int>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection('notifications')
      .doc(uid)
      .collection('items')
      .where('read', isEqualTo: false)
      .snapshots()
      .map((snap) => snap.docs.length);
});

// ── Screen ──────────────────────────────────────────────────────────────────

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _markAllRead(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .where('read', isEqualTo: false)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> _markRead(String uid, String notifId) async {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .doc(notifId)
        .update({'read': true});
  }

  void _handleTap(
    BuildContext context,
    NotificationItem notif,
    String uid,
  ) async {
    await _markRead(uid, notif.id);

    if (!context.mounted) return;

    switch (notif.screen) {
      case 'driverProfile':
        if (notif.rideId != null) {
          context.push(AppRoutes.driverProfile,
              extra: {'rideId': notif.rideId!});
        }
      case 'rideRequests':
        if (notif.rideId != null) {
          context.push('/ride-requests/${notif.rideId}');
        }
      case 'chat':
        if (notif.chatId != null) {
          context.push(AppRoutes.chat, extra: {
            'chatId': notif.chatId!,
            'otherUserName': notif.title,
          });
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final notifAsync = ref.watch(notificationsProvider);

    return Scaffold(
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
          'Notifications',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _markAllRead(uid),
            child: const Text(
              'Mark all read',
              style: TextStyle(
                color: AppColors.primaryMid,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      body: notifAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryMid),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (notifications) {
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none_rounded,
                      size: 56, color: AppColors.primaryLight),
                  const SizedBox(height: 16),
                  const Text(
                    'No notifications yet',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 15),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final notif = notifications[i];
              return _NotificationCard(
                notif: notif,
                onTap: () => _handleTap(context, notif, uid),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Card ─────────────────────────────────────────────────────────────────────

class _NotificationCard extends StatelessWidget {
  final NotificationItem notif;
  final VoidCallback onTap;

  const _NotificationCard({required this.notif, required this.onTap});

  IconData _iconForScreen(String? screen) {
    switch (screen) {
      case 'chat':
        return Icons.chat_bubble_outline_rounded;
      case 'rideRequests':
        return Icons.directions_car_rounded;
      case 'driverProfile':
        return Icons.check_circle_outline_rounded;
      default:
        return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatTime(notif.createdAt);
    final isUnread = !notif.read;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isUnread
              ? AppColors.primaryMid.withOpacity(0.07)
              : AppColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primaryMid.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _iconForScreen(notif.screen),
                color: AppColors.primaryMid,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notif.title,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: isUnread
                                ? FontWeight.w700
                                : FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (isUnread)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryMid,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notif.body,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            // Chevron if tappable
            if (notif.screen != null)
              const Padding(
                padding: EdgeInsets.only(left: 8, top: 2),
                child: Icon(Icons.chevron_right,
                    color: AppColors.textMuted, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('d MMM').format(dt);
  }
}
