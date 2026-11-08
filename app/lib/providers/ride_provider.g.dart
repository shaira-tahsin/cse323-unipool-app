// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ride_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$upcomingRidesHash() => r'47a05ef722e91a0ff25283cff083a174d3654d5c';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// See also [upcomingRides].
@ProviderFor(upcomingRides)
const upcomingRidesProvider = UpcomingRidesFamily();

/// See also [upcomingRides].
class UpcomingRidesFamily extends Family<AsyncValue<List<RideModel>>> {
  /// See also [upcomingRides].
  const UpcomingRidesFamily();

  /// See also [upcomingRides].
  UpcomingRidesProvider call(
    String uid,
  ) {
    return UpcomingRidesProvider(
      uid,
    );
  }

  @override
  UpcomingRidesProvider getProviderOverride(
    covariant UpcomingRidesProvider provider,
  ) {
    return call(
      provider.uid,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'upcomingRidesProvider';
}

/// See also [upcomingRides].
class UpcomingRidesProvider extends AutoDisposeStreamProvider<List<RideModel>> {
  /// See also [upcomingRides].
  UpcomingRidesProvider(
    String uid,
  ) : this._internal(
          (ref) => upcomingRides(
            ref as UpcomingRidesRef,
            uid,
          ),
          from: upcomingRidesProvider,
          name: r'upcomingRidesProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$upcomingRidesHash,
          dependencies: UpcomingRidesFamily._dependencies,
          allTransitiveDependencies:
              UpcomingRidesFamily._allTransitiveDependencies,
          uid: uid,
        );

  UpcomingRidesProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.uid,
  }) : super.internal();

  final String uid;

  @override
  Override overrideWith(
    Stream<List<RideModel>> Function(UpcomingRidesRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: UpcomingRidesProvider._internal(
        (ref) => create(ref as UpcomingRidesRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        uid: uid,
      ),
    );
  }

  @override
  AutoDisposeStreamProviderElement<List<RideModel>> createElement() {
    return _UpcomingRidesProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is UpcomingRidesProvider && other.uid == uid;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, uid.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin UpcomingRidesRef on AutoDisposeStreamProviderRef<List<RideModel>> {
  /// The parameter `uid` of this provider.
  String get uid;
}

class _UpcomingRidesProviderElement
    extends AutoDisposeStreamProviderElement<List<RideModel>>
    with UpcomingRidesRef {
  _UpcomingRidesProviderElement(super.provider);

  @override
  String get uid => (origin as UpcomingRidesProvider).uid;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
