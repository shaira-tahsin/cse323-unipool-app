/// A location chosen by the user via the Places autocomplete picker.
class PickedLocation {
  final String name;
  final double lat;
  final double lng;

  const PickedLocation({
    required this.name,
    required this.lat,
    required this.lng,
  });
}
