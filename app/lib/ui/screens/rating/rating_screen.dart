import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../widgets/primary_button.dart';

/// Called after a ride is marked completed.
///
/// [rideId]      — the ride that just finished
/// [toUid]       — the user being rated
/// [toName]      — display name of the user being rated
/// [role]        — 'driver' rating a passenger, or 'passenger' rating the driver
class RatingScreen extends ConsumerStatefulWidget {
  final String rideId;
  final String toUid;
  final String toName;
  final String role; // 'driver' | 'passenger'

  const RatingScreen({
    super.key,
    required this.rideId,
    required this.toUid,
    required this.toName,
    required this.role,
  });

  @override
  ConsumerState<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends ConsumerState<RatingScreen> {
  int _selectedStars = 0;
  bool _submitting = false;

  Future<void> _submit() async {
    if (_selectedStars == 0) return;

    final fromUid = FirebaseAuth.instance.currentUser?.uid;
    if (fromUid == null) return;

    setState(() => _submitting = true);

    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Write the rating doc (idempotent — rideId_fromUid is unique)
      await firestore
          .collection('ratings')
          .doc('${widget.rideId}_$fromUid')
          .set({
        'rideId': widget.rideId,
        'fromUid': fromUid,
        'toUid': widget.toUid,
        'score': _selectedStars,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2. Update the rated user's running average in /users/{toUid}
      await firestore.runTransaction((tx) async {
        final userRef = firestore.collection('users').doc(widget.toUid);
        final snap = await tx.get(userRef);
        if (!snap.exists) return;

        final data = snap.data()!;
        final currentRating = (data['rating'] as num?)?.toDouble() ?? 0.0;
        final totalRides = (data['totalRides'] as int?) ?? 0;

        // Rolling average: newAvg = (oldAvg * totalRides + newScore) / (totalRides + 1)
        final newTotal = totalRides + 1;
        final newRating =
            ((currentRating * totalRides) + _selectedStars) / newTotal;

        tx.update(userRef, {
          'rating': double.parse(newRating.toStringAsFixed(2)),
          'totalRides': newTotal,
        });
      });

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting rating: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRatingDriver = widget.role == 'passenger';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Skip button top right
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Avatar
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: AppColors.primaryMid,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isRatingDriver
                      ? Icons.directions_car_rounded
                      : Icons.person,
                  size: 48,
                  color: AppColors.white,
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Rate your ${isRatingDriver ? 'driver' : 'passenger'}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'How was your ride with ${widget.toName}?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 40),

              // Star row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final starIndex = i + 1;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedStars = starIndex),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        starIndex <= _selectedStars
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 48,
                        color: starIndex <= _selectedStars
                            ? const Color(0xFFFFC107)
                            : AppColors.primaryLight,
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 12),

              // Label under stars
              Text(
                _starLabel(_selectedStars),
                style: TextStyle(
                  color: _selectedStars > 0
                      ? AppColors.primaryMid
                      : AppColors.textMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const Spacer(),

              PrimaryButton(
                label: 'Submit Rating',
                isLoading: _submitting,
                onPressed: _selectedStars > 0 ? _submit : null,
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Skip for now',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  String _starLabel(int stars) {
    switch (stars) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Great';
      case 5:
        return 'Excellent!';
      default:
        return 'Tap a star to rate';
    }
  }
}
