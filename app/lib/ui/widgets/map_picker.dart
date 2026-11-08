import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/app_colors.dart';
import '../../../data/models/location_model.dart';

export '../../../data/models/location_model.dart' show PickedLocation;

// Sentinel result to signal "user wants to pick on map"
class _PickOnMapSignal extends PickedLocation {
  const _PickOnMapSignal()
      : super(name: '__pick_on_map__', lat: 0, lng: 0);
}

/// A tappable location field that opens a bottom sheet with Places autocomplete.
/// If [onPickOnMap] is provided, a "Pick on map" button appears in the sheet.
class MapPicker extends StatelessWidget {
  final String hint;
  final PickedLocation? value;
  final String apiKey;
  final ValueChanged<PickedLocation> onPicked;
  final VoidCallback? onPickOnMap;
  final IconData leadingIcon;

  const MapPicker({
    super.key,
    required this.hint,
    required this.apiKey,
    required this.onPicked,
    this.value,
    this.onPickOnMap,
    this.leadingIcon = Icons.radio_button_checked_outlined,
  });

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<PickedLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlacesSheet(
        apiKey: apiKey,
        hint: hint,
        showPickOnMap: onPickOnMap != null,
      ),
    );
    if (picked == null) return;
    if (picked is _PickOnMapSignal) {
      onPickOnMap?.call();
    } else {
      onPicked(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(leadingIcon, size: 18, color: AppColors.primaryMid),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value?.name ?? hint,
                style: TextStyle(
                  color: value == null
                      ? AppColors.textMuted
                      : AppColors.textPrimary,
                  fontSize: 15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal bottom-sheet
// ---------------------------------------------------------------------------

class _PlacesSheet extends StatefulWidget {
  final String apiKey;
  final String hint;
  final bool showPickOnMap;

  const _PlacesSheet({
    required this.apiKey,
    required this.hint,
    required this.showPickOnMap,
  });

  @override
  State<_PlacesSheet> createState() => _PlacesSheetState();
}

class _PlacesSheetState extends State<_PlacesSheet> {
  final TextEditingController _ctrl = TextEditingController();
  List<_Prediction> _predictions = [];
  bool _loading = false;

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeQueryComponent(query)}'
        '&key=${widget.apiKey}'
        '&components=country:bd'
        '&language=en',
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final preds = (json['predictions'] as List? ?? [])
            .map((e) => _Prediction.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() => _predictions = preds);
      }
    } catch (_) {
      // silently fail — user can retry typing
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<PickedLocation?> _fetchDetails(String placeId) async {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=$placeId'
      '&fields=geometry,formatted_address,name'
      '&key=${widget.apiKey}',
    );
    final res = await http.get(uri);
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final result = json['result'] as Map<String, dynamic>?;
      if (result != null) {
        final loc =
            (result['geometry'] as Map)['location'] as Map<String, dynamic>;
        return PickedLocation(
          name: result['formatted_address'] as String? ??
              result['name'] as String? ??
              '',
          lat: (loc['lat'] as num).toDouble(),
          lng: (loc['lng'] as num).toDouble(),
        );
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withOpacity(0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          // Search field
          TextField(
            controller: _ctrl,
            autofocus: true,
            onChanged: _search,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(color: AppColors.textMuted),
              prefixIcon: const Icon(Icons.search, color: AppColors.primaryMid),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryMid,
                        ),
                      ),
                    )
                  : widget.showPickOnMap
                      ? IconButton(
                          tooltip: 'Pick on map',
                          icon: const Icon(Icons.map_outlined,
                              color: AppColors.primaryMid),
                          onPressed: () => Navigator.of(context)
                              .pop(const _PickOnMapSignal()),
                        )
                      : null,
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Results list
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.35,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _predictions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = _predictions[i];
                return ListTile(
                  leading: const Icon(Icons.location_on_outlined,
                      color: AppColors.primaryMid),
                  title: Text(
                    p.mainText,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  subtitle: p.secondaryText.isNotEmpty
                      ? Text(
                          p.secondaryText,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textMuted),
                        )
                      : null,
                  onTap: () async {
                    final loc = await _fetchDetails(p.placeId);
                    if (loc != null && context.mounted) {
                      Navigator.of(context).pop(loc);
                    }
                  },
                );
              },
            ),
          ),


        ],
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Autocomplete prediction model
// ---------------------------------------------------------------------------

class _Prediction {
  final String placeId;
  final String mainText;
  final String secondaryText;

  const _Prediction({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });

  factory _Prediction.fromJson(Map<String, dynamic> json) {
    final structured =
        json['structured_formatting'] as Map<String, dynamic>? ?? {};
    return _Prediction(
      placeId: json['place_id'] as String? ?? '',
      mainText: structured['main_text'] as String? ?? '',
      secondaryText: structured['secondary_text'] as String? ?? '',
    );
  }
}
