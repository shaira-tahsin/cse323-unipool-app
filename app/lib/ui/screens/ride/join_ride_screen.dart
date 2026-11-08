import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../data/models/location_model.dart';
import '../../../data/repositories/ride_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/ride_provider.dart';
import '../../widgets/map_picker.dart';
import '../../widgets/primary_button.dart';

const _kMapsApiKey = String.fromEnvironment('MAPS_API_KEY');

enum _ActiveField { none, from, to }

class JoinRideScreen extends ConsumerStatefulWidget {
  const JoinRideScreen({super.key});

  @override
  ConsumerState<JoinRideScreen> createState() => _JoinRideScreenState();
}

class _JoinRideScreenState extends ConsumerState<JoinRideScreen> {
  GoogleMapController? _mapController;

  PickedLocation? _from;
  PickedLocation? _to;
  DateTime? _departureTime; // ← new

  _ActiveField _activeField = _ActiveField.none;
  LatLng _mapCenter = const LatLng(23.8103, 90.4125);
  bool _reverseGeocoding = false;
  String _liveAddress = '';
  Timer? _debounceTimer;

  static const _dhakaLatLng = LatLng(23.8103, 90.4125);

  bool get _isPickingOnMap => _activeField != _ActiveField.none;

  // ── Markers ───────────────────────────────────────────────────────────────

  Set<Marker> get _markers {
    final markers = <Marker>{};
    if (_from != null) {
      markers.add(Marker(
        markerId: const MarkerId('from'),
        position: LatLng(_from!.lat, _from!.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: 'From', snippet: _from!.name),
      ));
    }
    if (_to != null) {
      markers.add(Marker(
        markerId: const MarkerId('to'),
        position: LatLng(_to!.lat, _to!.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        infoWindow: InfoWindow(title: 'To', snippet: _to!.name),
      ));
    }
    return markers;
  }

  void _onFromPicked(PickedLocation loc) {
    setState(() => _from = loc);
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(loc.lat, loc.lng), 13),
    );
  }

  void _onToPicked(PickedLocation loc) {
    setState(() => _to = loc);
    if (_from != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          _from!.lat < loc.lat ? _from!.lat : loc.lat,
          _from!.lng < loc.lng ? _from!.lng : loc.lng,
        ),
        northeast: LatLng(
          _from!.lat > loc.lat ? _from!.lat : loc.lat,
          _from!.lng > loc.lng ? _from!.lng : loc.lng,
        ),
      );
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    } else {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(loc.lat, loc.lng), 13),
      );
    }
  }

  // ── Crosshair / picking mode ──────────────────────────────────────────────

  void _enterPickingMode(_ActiveField field) async {
    setState(() {
      _activeField = field;
      _liveAddress = '';
    });
    if (_mapController != null) {
      final region = await _mapController!.getVisibleRegion();
      final center = LatLng(
        (region.northeast.latitude + region.southwest.latitude) / 2,
        (region.northeast.longitude + region.southwest.longitude) / 2,
      );
      _mapCenter = center;
      _scheduleLiveGeocode(center);
    }
  }

  void _cancelPickingMode() {
    _debounceTimer?.cancel();
    setState(() {
      _activeField = _ActiveField.none;
      _liveAddress = '';
    });
  }

  void _onCameraMove(CameraPosition pos) {
    _mapCenter = pos.target;
    _scheduleLiveGeocode(pos.target);
  }

  void _scheduleLiveGeocode(LatLng target) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () async {
      final address = await _reverseGeocode(target);
      if (mounted && _isPickingOnMap) {
        setState(() => _liveAddress = address);
      }
    });
  }

  Future<void> _confirmMapLocation() async {
    _debounceTimer?.cancel();
    setState(() => _reverseGeocoding = true);
    try {
      final address = await _reverseGeocode(_mapCenter);
      final loc = PickedLocation(
        name: address.isNotEmpty
            ? address
            : '${_mapCenter.latitude.toStringAsFixed(5)}, ${_mapCenter.longitude.toStringAsFixed(5)}',
        lat: _mapCenter.latitude,
        lng: _mapCenter.longitude,
      );
      if (_activeField == _ActiveField.from) {
        _onFromPicked(loc);
      } else {
        _onToPicked(loc);
      }
    } finally {
      if (mounted) {
        setState(() {
          _reverseGeocoding = false;
          _activeField = _ActiveField.none;
          _liveAddress = '';
        });
      }
    }
  }

  Future<String> _reverseGeocode(LatLng latLng) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${latLng.latitude},${latLng.longitude}'
        '&key=$_kMapsApiKey',
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final results = json['results'] as List?;
        if (results != null && results.isNotEmpty) {
          return (results[0] as Map<String, dynamic>)['formatted_address']
                  as String? ??
              '';
        }
      }
    } catch (_) {}
    return '';
  }

  // ── Date / time picker ───────────────────────────────────────────────────

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: AppColors.white,
            surface: AppColors.background,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: AppColors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (time == null) return;

    setState(() {
      _departureTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String get _timeLabel {
    if (_departureTime == null) return 'Departure time';
    final d = _departureTime!;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${months[d.month - 1]} ${d.day}  •  $h:$m $ampm';
  }

  // ── Find ride ─────────────────────────────────────────────────────────────

  Future<void> _findRide() async {
    if (_to == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination.')),
      );
      return;
    }

    if (_departureTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a departure time.')),
      );
      return;
    }

    // NSU endpoint check
    final fromIsNsu = _from != null && isNsuLocation(_from!.lat, _from!.lng);
    final toIsNsu = isNsuLocation(_to!.lat, _to!.lng);
    if (!fromIsNsu && !toIsNsu) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('One endpoint must be North South University.')),
      );
      return;
    }

    // One active ride check
    final user = ref.read(userProfileProvider).valueOrNull;
    if (user != null) {
      final repo = ref.read(rideRepositoryProvider);
      final alreadyPassenger = await repo.hasActiveRideAsPassenger(user.uid);
      if (alreadyPassenger && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('You already have an active ride. Complete it first.')),
        );
        return;
      }
    }

    if (!mounted) return;
    context.push(
      AppRoutes.rideResults,
      extra: {
        'fromName': _from?.name ?? '',
        'fromLat': _from?.lat ?? 0.0,
        'fromLng': _from?.lng ?? 0.0,
        'toName': _to!.name,
        'toLat': _to!.lat,
        'toLng': _to!.lng,
        'departureTime': _departureTime!.millisecondsSinceEpoch, // ← new
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Map area ──────────────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: _dhakaLatLng,
                    zoom: 12,
                  ),
                  onMapCreated: (c) => _mapController = c,
                  markers: _isPickingOnMap ? {} : _markers,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  onCameraMove: _isPickingOnMap ? _onCameraMove : null,
                ),

                // Crosshair
                if (_isPickingOnMap) const Center(child: _CrosshairIcon()),

                // Confirm Location button
                if (_isPickingOnMap)
                  Positioned(
                    bottom: 16,
                    left: 20,
                    right: 20,
                    child: _reverseGeocoding
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primary),
                          )
                        : PrimaryButton(
                            label: 'Confirm Location',
                            backgroundColor: AppColors.primary,
                            onPressed: _confirmMapLocation,
                          ),
                  ),

                // Back / Cancel button
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  child: _FloatingIconButton(
                    icon: _isPickingOnMap
                        ? Icons.close_rounded
                        : Icons.arrow_back_ios_new_rounded,
                    onTap: _isPickingOnMap
                        ? _cancelPickingMode
                        : () => context.pop(),
                  ),
                ),

                // Title / picking label / live address
                if (!_isPickingOnMap)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 10,
                    left: 0,
                    right: 0,
                    child: const Center(
                      child: Text(
                        'Join Ride',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                      ),
                    ),
                  ),

                if (_isPickingOnMap)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 10,
                    left: 56,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.dark.withOpacity(0.82),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _liveAddress.isNotEmpty
                            ? _liveAddress
                            : (_activeField == _ActiveField.from
                                ? 'Move map to set pickup'
                                : 'Move map to set drop-off'),
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Form ──────────────────────────────────────────────────────────
          if (!_isPickingOnMap)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                children: [
                  // From field
                  MapPicker(
                    hint: 'Going from',
                    value: _from,
                    apiKey: _kMapsApiKey,
                    onPicked: _onFromPicked,
                    onPickOnMap: () => _enterPickingMode(_ActiveField.from),
                    leadingIcon: Icons.radio_button_checked_outlined,
                  ),
                  const SizedBox(height: 10),

                  // To field with + button
                  Row(
                    children: [
                      Expanded(
                        child: MapPicker(
                          hint: 'Going to',
                          value: _to,
                          apiKey: _kMapsApiKey,
                          onPicked: _onToPicked,
                          onPickOnMap: () => _enterPickingMode(_ActiveField.to),
                          leadingIcon: Icons.location_on_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          // Future: add waypoints
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.add,
                              color: AppColors.primaryMid, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Time picker ──────────────────────────────────────────
                  GestureDetector(
                    onTap: _pickDateTime,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time_rounded,
                              size: 18, color: AppColors.primaryMid),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _timeLabel,
                              style: TextStyle(
                                fontSize: 13,
                                color: _departureTime == null
                                    ? AppColors.textMuted
                                    : AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  PrimaryButton(
                    label: 'Find Ride',
                    backgroundColor: AppColors.primary,
                    onPressed: _findRide,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────

class _CrosshairIcon extends StatelessWidget {
  const _CrosshairIcon();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 2, height: 20, color: AppColors.primary),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 2.5),
              color: AppColors.primary.withOpacity(0.15),
            ),
          ),
          Container(width: 2, height: 20, color: AppColors.primary),
        ],
      ),
    );
  }
}

class _FloatingIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _FloatingIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.background,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 16, color: AppColors.dark),
      ),
    );
  }
}
