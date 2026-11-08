import 'package:cloud_firestore/cloud_firestore.dart';

class LocationData {
  final String name;
  final double lat;
  final double lng;

  const LocationData({
    required this.name,
    required this.lat,
    required this.lng,
  });

  factory LocationData.fromMap(Map<String, dynamic> map) {
    return LocationData(
      name: map['name'] as String? ?? '',
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'lat': lat,
        'lng': lng,
      };
}

class RideModel {
  final String id;
  final String driverId;
  final String driverName;
  final String licencePlate;
  final LocationData fromLocation;
  final LocationData toLocation;
  final Timestamp departureTime;
  final int availableSeats;
  final int fare;
  final String status; // open | full | completed | cancelled
  final List<String> passengerIds;
  final String universityDomain;
  final Timestamp createdAt;

  // NEW — Step 7b
  // Written by the driver's device via updateDriverLocation().
  // Null until the driver opens ActiveRideScreen for the first time.
  final Map<String, double>? driverLocation;

  const RideModel({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.licencePlate,
    required this.fromLocation,
    required this.toLocation,
    required this.departureTime,
    required this.availableSeats,
    required this.fare,
    required this.status,
    required this.passengerIds,
    required this.universityDomain,
    required this.createdAt,
    this.driverLocation,
  });

  factory RideModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RideModel(
      id: doc.id,
      driverId: data['driverId'] as String? ?? '',
      driverName: data['driverName'] as String? ?? '',
      licencePlate: data['licencePlate'] as String? ?? '',
      fromLocation:
          LocationData.fromMap(data['fromLocation'] as Map<String, dynamic>? ?? {}),
      toLocation:
          LocationData.fromMap(data['toLocation'] as Map<String, dynamic>? ?? {}),
      departureTime: data['departureTime'] as Timestamp? ?? Timestamp.now(),
      availableSeats: data['availableSeats'] as int? ?? 0,
      fare: data['fare'] as int? ?? 0,
      status: data['status'] as String? ?? 'open',
      passengerIds: List<String>.from(data['passengerIds'] as List? ?? []),
      universityDomain: data['universityDomain'] as String? ?? '',
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
      // Parse driverLocation map — keys are always 'lat' and 'lng'
      driverLocation: (data['driverLocation'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }

  Map<String, dynamic> toMap() => {
        'driverId': driverId,
        'driverName': driverName,
        'licencePlate': licencePlate,
        'fromLocation': fromLocation.toMap(),
        'toLocation': toLocation.toMap(),
        'departureTime': departureTime,
        'availableSeats': availableSeats,
        'fare': fare,
        'status': status,
        'passengerIds': passengerIds,
        'universityDomain': universityDomain,
        'createdAt': createdAt,
        if (driverLocation != null) 'driverLocation': driverLocation,
      };
}
