import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/models/ride_model.dart';
import '../data/models/location_model.dart';
import '../data/repositories/ride_repository.dart';

part 'ride_provider.g.dart';

final rideRepositoryProvider = Provider<RideRepository>((ref) {
  return RideRepository();
});

// ── Upcoming rides stream (code-generated — do not rename) ───────────────

@riverpod
Stream<List<RideModel>> upcomingRides(UpcomingRidesRef ref, String uid) {
  final repo = ref.watch(rideRepositoryProvider);
  return repo.upcomingRidesStream(uid);
}

// ── Offer ride notifier ──────────────────────────────────────────────────

class OfferRideNotifier extends StateNotifier<AsyncValue<void>> {
  final RideRepository _repo;

  OfferRideNotifier(this._repo) : super(const AsyncValue.data(null));

  Future<void> offerRide({
    required String driverId,
    required String driverName,
    required String licencePlate,
    required PickedLocation from,
    required PickedLocation to,
    required DateTime departureTime,
    required int seats,
    required int fare,
    required String universityDomain,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repo.createRide({
        'driverId': driverId,
        'driverName': driverName,
        'licencePlate': licencePlate,
        'fromLocation': {
          'name': from.name,
          'lat': from.lat,
          'lng': from.lng,
        },
        'toLocation': {
          'name': to.name,
          'lat': to.lat,
          'lng': to.lng,
        },
        'departureTime': Timestamp.fromDate(departureTime),
        'availableSeats': seats,
        'fare': fare,
        'status': 'open',
        'passengerIds': <String>[],
        'universityDomain': universityDomain,
      });
    });
  }
}

final offerRideProvider =
    StateNotifierProvider<OfferRideNotifier, AsyncValue<void>>((ref) {
  return OfferRideNotifier(ref.read(rideRepositoryProvider));
});

// ── Join request status stream (passenger side) ──────────────────────────

final requestStatusStreamProvider =
    StreamProvider.family<String?, ({String rideId, String passengerId})>(
  (ref, args) {
    final repo = ref.watch(rideRepositoryProvider);
    return repo.requestStatusStream(
      rideId: args.rideId,
      passengerId: args.passengerId,
    );
  },
);

// ── Join request action notifier (passenger side) ────────────────────────

class JoinRequestNotifier extends StateNotifier<AsyncValue<void>> {
  final RideRepository _repo;

  JoinRequestNotifier(this._repo) : super(const AsyncValue.data(null));

  Future<void> sendRequest(String rideId, String passengerId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repo.sendJoinRequest(
        rideId: rideId,
        passengerId: passengerId,
      ),
    );
  }
}

final joinRequestProvider =
    StateNotifierProvider<JoinRequestNotifier, AsyncValue<void>>((ref) {
  return JoinRequestNotifier(ref.read(rideRepositoryProvider));
});

// ── Incoming join requests stream (driver side) ──────────────────────────

final joinRequestsStreamProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>(
  (ref, rideId) {
    final repo = ref.watch(rideRepositoryProvider);
    return repo.getJoinRequests(rideId);
  },
);

// ── Accept / Reject notifier (driver side) ───────────────────────────────

class RideRequestActionNotifier extends StateNotifier<AsyncValue<void>> {
  final RideRepository _repo;

  RideRequestActionNotifier(this._repo) : super(const AsyncValue.data(null));

  Future<void> accept(String rideId, String passengerId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repo.acceptRequest(
        rideId: rideId,
        passengerId: passengerId,
      ),
    );
  }

  Future<void> reject(String rideId, String passengerId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repo.rejectRequest(
        rideId: rideId,
        passengerId: passengerId,
      ),
    );
  }
}

final rideRequestActionProvider =
    StateNotifierProvider<RideRequestActionNotifier, AsyncValue<void>>((ref) {
  return RideRequestActionNotifier(ref.read(rideRepositoryProvider));
});

// ── Real-time single ride stream — NEW Step 7c ───────────────────────────
// Watches a single ride doc and emits a fresh RideModel on every change.
// Usage: ref.watch(rideStreamProvider(rideId))

final rideStreamProvider = StreamProvider.family<RideModel?, String>(
  (ref, rideId) {
    final repo = ref.watch(rideRepositoryProvider);
    return repo.rideStream(rideId);
  },
);

// ── Driver location updater — NEW Step 7c ────────────────────────────────
// Wraps updateDriverLocation() in an AsyncNotifier so the UI can call it
// and observe loading / error state.
// Usage: ref.read(driverLocationProvider.notifier).update(rideId, lat, lng)

class DriverLocationNotifier extends StateNotifier<AsyncValue<void>> {
  final RideRepository _repo;

  DriverLocationNotifier(this._repo) : super(const AsyncValue.data(null));

  Future<void> update(String rideId, double lat, double lng) async {
    // No loading state here — location pings are fire-and-forget.
    // Errors are swallowed silently to avoid UI flicker on every GPS tick.
    try {
      await _repo.updateDriverLocation(rideId, lat, lng);
    } catch (_) {
      // GPS pings are best-effort; a missed write doesn't need to surface.
    }
  }
}

final driverLocationProvider =
    StateNotifierProvider<DriverLocationNotifier, AsyncValue<void>>((ref) {
  return DriverLocationNotifier(ref.read(rideRepositoryProvider));
});
