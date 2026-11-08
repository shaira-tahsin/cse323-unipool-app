import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
import '../models/ride_model.dart';

// NSU Bashundhara Campus coordinates
const double kNsuLat = 23.8153;
const double kNsuLng = 90.4244;
const double kNsuRadiusKm = 0.5; // within 500 m counts as "NSU"

// ±10 minutes window for departure time matching
const int kDepartureWindowMinutes = 10;

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371.0;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  final c = 2 * math.asin(math.sqrt(a));
  return earthRadius * c;
}

double _toRad(double deg) => deg * math.pi / 180;

/// Returns true if the given coordinates are within [kNsuRadiusKm] of NSU.
bool isNsuLocation(double lat, double lng) {
  return _haversineKm(lat, lng, kNsuLat, kNsuLng) <= kNsuRadiusKm;
}

class RideRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Upcoming rides (home screen) ─────────────────────────────────────────

  Stream<List<RideModel>> userRidesStream(String uid) {
    return _firestore
        .collection('rides')
        .where('driverId', isEqualTo: uid)
        .where('status', whereIn: ['open', 'full', 'active'])
        .orderBy('departureTime')
        .snapshots()
        .map((snap) => snap.docs.map(RideModel.fromDoc).toList());
  }

  Stream<List<RideModel>> passengerRidesStream(String uid) {
    return _firestore
        .collection('rides')
        .where('passengerIds', arrayContains: uid)
        .where('status', whereIn: ['open', 'full', 'active'])
        .orderBy('departureTime')
        .snapshots()
        .map((snap) => snap.docs.map(RideModel.fromDoc).toList());
  }

  Stream<List<RideModel>> upcomingRidesStream(String uid) {
    return CombineLatestStream.combine2(
      userRidesStream(uid),
      passengerRidesStream(uid),
      (List<RideModel> driverRides, List<RideModel> passengerRides) {
        final all = [...driverRides, ...passengerRides];
        all.sort((a, b) => a.departureTime.compareTo(b.departureTime));
        return all;
      },
    );
  }

  // ── Active ride checks ───────────────────────────────────────────────────

  Future<bool> hasActiveRideAsDriver(String uid) async {
    final snap = await _firestore
        .collection('rides')
        .where('driverId', isEqualTo: uid)
        .where('status', whereIn: ['open', 'full', 'active'])
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<bool> hasActiveRideAsPassenger(String uid) async {
    final snap = await _firestore
        .collection('rides')
        .where('passengerIds', arrayContains: uid)
        .where('status', whereIn: ['open', 'full', 'active'])
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  // ── Create ride ──────────────────────────────────────────────────────────

  Future<String> createRide(Map<String, dynamic> rideData) async {
    final doc = await _firestore.collection('rides').add({
      ...rideData,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  // ── Search rides ─────────────────────────────────────────────────────────

  Future<List<RideModel>> searchRides({
    required String universityDomain,
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    String? excludeUid,
    DateTime? departureTime,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('rides')
        .where('universityDomain', isEqualTo: universityDomain)
        .where('status', isEqualTo: 'open');

    if (departureTime != null) {
      final window = Duration(minutes: kDepartureWindowMinutes);
      final earliest = Timestamp.fromDate(departureTime.subtract(window));
      final latest = Timestamp.fromDate(departureTime.add(window));
      query = query
          .where('departureTime', isGreaterThanOrEqualTo: earliest)
          .where('departureTime', isLessThanOrEqualTo: latest);
    }

    query = query.orderBy('departureTime');

    final snap = await query.get();
    final rides = snap.docs.map(RideModel.fromDoc).toList();

    return rides.where((r) {
      if (excludeUid != null && r.driverId == excludeUid) return false;

      final driverHasNsu =
          isNsuLocation(r.fromLocation.lat, r.fromLocation.lng) ||
              isNsuLocation(r.toLocation.lat, r.toLocation.lng);
      if (!driverHasNsu) return false;

      final destDist = _haversineKm(
        r.toLocation.lat,
        r.toLocation.lng,
        toLat,
        toLng,
      );
      if (destDist <= 5.0) return true;

      final alongRoute = _distToSegmentKm(
        pointLat: toLat,
        pointLng: toLng,
        segALat: r.fromLocation.lat,
        segALng: r.fromLocation.lng,
        segBLat: r.toLocation.lat,
        segBLng: r.toLocation.lng,
      );
      return alongRoute <= 1.0;
    }).toList();
  }

  // ── Fetch single ride ────────────────────────────────────────────────────

  Future<RideModel?> getRide(String rideId) async {
    final doc = await _firestore.collection('rides').doc(rideId).get();
    if (!doc.exists) return null;
    return RideModel.fromDoc(doc);
  }

  // ── User helpers ─────────────────────────────────────────────────────────
  // NEW — Step 7a
  // Fetches a user's display name from /users/{uid}.
  // Used by ActiveRideScreen to show passenger names.

  Future<String> getUserName(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data()?['name'] as String? ?? 'Passenger';
  }

  // ── Real-time single ride stream ─────────────────────────────────────────
  // NEW — Step 7c
  // Emits a fresh RideModel every time the ride doc changes in Firestore.
  // Used by ActiveRideScreen (driver) and ActiveRideMapScreen (passenger).

  Stream<RideModel?> rideStream(String rideId) {
    return _firestore
        .collection('rides')
        .doc(rideId)
        .snapshots()
        .map((doc) => doc.exists ? RideModel.fromDoc(doc) : null);
  }

  // ── Driver location update ───────────────────────────────────────────────
  // NEW — Step 7c
  // Called repeatedly by the driver's device (via flutter_background_service
  // or a periodic timer) to push their current GPS position into Firestore.
  // Passengers read this field via rideStream() to show the live map.

  Future<void> updateDriverLocation(
    String rideId,
    double lat,
    double lng,
  ) async {
    await _firestore.collection('rides').doc(rideId).update({
      'driverLocation': {'lat': lat, 'lng': lng},
    });
  }

  // ── Join requests ────────────────────────────────────────────────────────

  Future<void> sendJoinRequest({
    required String rideId,
    required String passengerId,
  }) async {
    await _firestore
        .collection('rides')
        .doc(rideId)
        .collection('requests')
        .doc(passengerId)
        .set({
      'passengerId': passengerId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String?> getRequestStatus({
    required String rideId,
    required String passengerId,
  }) async {
    final doc = await _firestore
        .collection('rides')
        .doc(rideId)
        .collection('requests')
        .doc(passengerId)
        .get();
    if (!doc.exists) return null;
    return doc.data()?['status'] as String?;
  }

  Stream<String?> requestStatusStream({
    required String rideId,
    required String passengerId,
  }) {
    return _firestore
        .collection('rides')
        .doc(rideId)
        .collection('requests')
        .doc(passengerId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return doc.data()?['status'] as String?;
    });
  }

  Stream<List<Map<String, dynamic>>> getJoinRequests(String rideId) {
    return _firestore
        .collection('rides')
        .doc(rideId)
        .collection('requests')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Future<void> acceptRequest({
    required String rideId,
    required String passengerId,
  }) async {
    final rideRef = _firestore.collection('rides').doc(rideId);
    final requestRef = rideRef.collection('requests').doc(passengerId);

    await _firestore.runTransaction((tx) async {
      final rideSnap = await tx.get(rideRef);
      if (!rideSnap.exists) throw Exception('Ride not found');

      final currentSeats = (rideSnap.data()?['availableSeats'] as int?) ?? 0;
      final newSeats = (currentSeats - 1).clamp(0, 999);
      final newStatus = newSeats == 0 ? 'full' : 'open';

      tx.update(requestRef, {'status': 'accepted'});
      tx.update(rideRef, {
        'passengerIds': FieldValue.arrayUnion([passengerId]),
        'availableSeats': newSeats,
        'status': newStatus,
      });
    });
  }

  Future<void> rejectRequest({
    required String rideId,
    required String passengerId,
  }) async {
    await _firestore
        .collection('rides')
        .doc(rideId)
        .collection('requests')
        .doc(passengerId)
        .update({'status': 'rejected'});
  }

  // ── FCM token ────────────────────────────────────────────────────────────

  Future<void> saveFcmToken(String uid, String token) async {
    await _firestore.collection('users').doc(uid).update({
      'fcmToken': token,
    });
  }

  // ── Cancel / leave ride ──────────────────────────────────────────────────

  Future<void> startRide(String rideId) async {
    await _firestore.collection('rides').doc(rideId).update({
      'status': 'active',
    });
  }

  Future<void> cancelRide(String rideId) async {
    await _firestore.collection('rides').doc(rideId).update({
      'status': 'cancelled',
    });
  }

  Future<void> leaveRide({
    required String rideId,
    required String passengerId,
  }) async {
    await _firestore.collection('rides').doc(rideId).update({
      'passengerIds': FieldValue.arrayRemove([passengerId]),
      'availableSeats': FieldValue.increment(1),
      'status': 'open',
    });
  }

  // ── Distance helpers ─────────────────────────────────────────────────────

  static double _distToSegmentKm({
    required double pointLat,
    required double pointLng,
    required double segALat,
    required double segALng,
    required double segBLat,
    required double segBLng,
  }) {
    const latKm = 111.0;
    final lngKm = 111.0 * math.cos(_toRad((segALat + segBLat) / 2));

    final px = (pointLng - segALng) * lngKm;
    final py = (pointLat - segALat) * latKm;
    final dx = (segBLng - segALng) * lngKm;
    final dy = (segBLat - segALat) * latKm;

    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return math.sqrt(px * px + py * py);

    final t = ((px * dx + py * dy) / lenSq).clamp(0.0, 1.0);
    final closestX = t * dx - px;
    final closestY = t * dy - py;
    return math.sqrt(closestX * closestX + closestY * closestY);
  }
}
