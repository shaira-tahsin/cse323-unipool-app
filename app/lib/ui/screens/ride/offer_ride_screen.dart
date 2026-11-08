import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

// Which field is currently being set via map-tap
enum _ActiveField { none, from, to }

class OfferRideScreen extends ConsumerStatefulWidget {
  const OfferRideScreen({super.key});

  @override
  ConsumerState<OfferRideScreen> createState() => _OfferRideScreenState();
}

class _OfferRideScreenState extends ConsumerState<OfferRideScreen> {
  GoogleMapController? _mapController;

  PickedLocation? _from;
  PickedLocation? _to;
  DateTime? _departureTime;
  int _seats = 1;
  final TextEditingController _fareCtrl = TextEditingController();
  bool _submitting = false;

  // Crosshair / picking mode state
  _ActiveField _activeField = _ActiveField.none;
  LatLng _mapCenter = const LatLng(23.8103, 90.4125);
  bool _reverseGeocoding = false;
  String _liveAddress = '';
  Timer? _debounceTimer;

  static const _dhakaLatLng = LatLng(23.8103, 90.4125);

  bool get _isPickingOnMap => _activeField != _ActiveField.none;

  // ── Map markers ───────────────────────────────────────────────────────────

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

  // ── Crosshair / map-tap picking ──────────────────────────────────────────

  void _enterPickingMode(_ActiveField field) async {
    setState(() {
      _activeField = field;
      _liveAddress = '';
    });
    // Get the actual current camera center from the map controller
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
      } else if (_activeField == _ActiveField.to) {
        _onToPicked(loc);
      }
    } catch (_) {
      final loc = PickedLocation(
        name:
            '${_mapCenter.latitude.toStringAsFixed(5)}, ${_mapCenter.longitude.toStringAsFixed(5)}',
        lat: _mapCenter.latitude,
        lng: _mapCenter.longitude,
      );
      if (_activeField == _ActiveField.from) {
        _onFromPicked(loc);
      } else if (_activeField == _ActiveField.to) {
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

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_from == null || _to == null) {
      _showSnack('Please select both pickup and drop-off locations.');
      return;
    }

    // NSU endpoint check
    final fromIsNsu = isNsuLocation(_from!.lat, _from!.lng);
    final toIsNsu = isNsuLocation(_to!.lat, _to!.lng);
    if (!fromIsNsu && !toIsNsu) {
      _showSnack('One endpoint must be North South University.');
      return;
    }

    if (_departureTime == null) {
      _showSnack('Please choose a departure time.');
      return;
    }
    final fareText = _fareCtrl.text.trim();
    final fare = int.tryParse(fareText);
    if (fare == null || fare <= 0) {
      _showSnack('Please enter a valid fare amount.');
      return;
    }

    final user = ref.read(userProfileProvider).valueOrNull;
    if (user == null) {
      _showSnack('Could not load your profile. Please try again.');
      return;
    }
    if (user.licencePlate == null || user.licencePlate!.isEmpty) {
      _showSnack('Add a licence plate to your profile before offering rides.');
      return;
    }

    setState(() => _submitting = true);
    try {
      // One active ride check
      final repo = ref.read(rideRepositoryProvider);
      final alreadyDriving = await repo.hasActiveRideAsDriver(user.uid);
      if (alreadyDriving) {
        if (mounted) {
          _showSnack('You already have an active ride. Complete or cancel it first.');
        }
        return;
      }

      await ref.read(offerRideProvider.notifier).offerRide(
            driverId: user.uid,
            driverName: user.name,
            licencePlate: user.licencePlate!,
            from: _from!,
            to: _to!,
            departureTime: _departureTime!,
            seats: _seats,
            fare: fare,
            universityDomain: user.universityDomain,
          );
      if (mounted) context.go(AppRoutes.home);
    } catch (_) {
      if (mounted) _showSnack('Failed to post ride. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Map area ─────────────────────────────────────────────────────
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

                // ── Crosshair (picking mode only) ──────────────────────────
                if (_isPickingOnMap)
                  const Center(
                    child: _CrosshairIcon(),
                  ),

                // ── Confirm Location button (picking mode) ─────────────────
                if (_isPickingOnMap)
                  Positioned(
                    bottom: 16,
                    left: 20,
                    right: 20,
                    child: _reverseGeocoding
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          )
                        : PrimaryButton(
                            label: 'Confirm Location',
                            backgroundColor: AppColors.primary,
                            onPressed: _confirmMapLocation,
                          ),
                  ),

                // ── Back / Cancel button ───────────────────────────────────
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

                // ── Screen title (hidden in picking mode) ──────────────────
                if (!_isPickingOnMap)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 10,
                    left: 0,
                    right: 0,
                    child: const Center(
                      child: Text(
                        'Offer Ride',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                      ),
                    ),
                  ),

                // ── Picking mode label + live address ─────────────────────
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

          // ── Form (hidden in picking mode) ─────────────────────────────────
          if (!_isPickingOnMap)
            Expanded(
              flex: 6,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // From
                    MapPicker(
                      hint: 'Going from',
                      value: _from,
                      apiKey: _kMapsApiKey,
                      onPicked: _onFromPicked,
                      onPickOnMap: () => _enterPickingMode(_ActiveField.from),
                      leadingIcon: Icons.radio_button_checked_outlined,
                    ),
                    const SizedBox(height: 10),

                    // To
                    MapPicker(
                      hint: 'Going to',
                      value: _to,
                      apiKey: _kMapsApiKey,
                      onPicked: _onToPicked,
                      onPickOnMap: () => _enterPickingMode(_ActiveField.to),
                      leadingIcon: Icons.location_on_outlined,
                    ),
                    const SizedBox(height: 10),

                    // Time + Seats
                    Row(
                      children: [
                        // Time
                        Expanded(
                          flex: 3,
                          child: GestureDetector(
                            onTap: _pickDateTime,
                            child: Container(
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
                        ),
                        const SizedBox(width: 10),

                        // Seat stepper
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.people_outline,
                                  size: 18, color: AppColors.primaryMid),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () {
                                  if (_seats > 1) setState(() => _seats--);
                                },
                                child: const Icon(Icons.remove,
                                    size: 18, color: AppColors.primaryMid),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '$_seats',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  if (_seats < 6) setState(() => _seats++);
                                },
                                child: const Icon(Icons.add,
                                    size: 18, color: AppColors.primaryMid),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Fare
                    TextField(
                      controller: _fareCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        hintText: 'Fare per passenger (Tk)',
                        hintStyle: const TextStyle(
                            color: AppColors.textMuted, fontSize: 15),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 14, right: 8, top: 2),
                          child: Text(
                            'Tk',
                            style: TextStyle(
                              color: AppColors.primaryMid,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        prefixIconConstraints:
                            const BoxConstraints(minWidth: 0, minHeight: 0),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 24),

                    PrimaryButton(
                      label: 'Offer Ride',
                      isLoading: _submitting,
                      onPressed: _submit,
                      backgroundColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _fareCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }
}

// ── Crosshair overlay icon ────────────────────────────────────────────────

class _CrosshairIcon extends StatelessWidget {
  const _CrosshairIcon();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 2,
            height: 20,
            color: AppColors.primary,
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 2.5),
              color: AppColors.primary.withOpacity(0.15),
            ),
          ),
          Container(
            width: 2,
            height: 20,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

// ── Floating map overlay button ───────────────────────────────────────────

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
