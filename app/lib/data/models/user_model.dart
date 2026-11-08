class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String? licencePlate;
  final String universityDomain;
  final String? avatarUrl;
  final double rating;
  final int totalRides;
  final DateTime createdAt;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    this.licencePlate,
    required this.universityDomain,
    this.avatarUrl,
    this.rating = 0.0,
    this.totalRides = 0,
    required this.createdAt,
  });

  factory UserModel.fromFirestore(Map<String, dynamic> data, String uid) {
    return UserModel(
      uid: uid,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      licencePlate: data['licencePlate'],
      universityDomain: data['universityDomain'] ?? 'northsouth.edu',
      avatarUrl: data['avatarUrl'],
      rating: (data['rating'] ?? 0.0).toDouble(),
      totalRides: data['totalRides'] ?? 0,
      createdAt: (data['createdAt'] as dynamic).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'licencePlate': licencePlate,
      'universityDomain': universityDomain,
      'avatarUrl': avatarUrl,
      'rating': rating,
      'totalRides': totalRides,
      'createdAt': createdAt,
    };
  }
}
