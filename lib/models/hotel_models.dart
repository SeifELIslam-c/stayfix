class UserRoles {
  static const String director = 'Directeur Général';
  static const String housekeepingManager = 'Directeur Gouvernante';
  static const String maintenanceManager = 'Directeur Maintenance';
  static const String receptionManager = 'Directeur Réception';
  static const String supervisor = 'Superviseur';
  static const String houseman = 'Houseman';
  static const String housekeeping = 'Valet/Femme de chambre';
  static const String staff = 'Staff';
}

class HotelUser {
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String username;
  final String role;
  final String phone;
  final String? hotelId;

  HotelUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.role,
    required this.phone,
    this.hotelId,
  });

  String get fullName => "$firstName $lastName";
}

class Hotel {
  final String id;
  final String groupId;
  final String name;
  final String location;
  final String ownerId;

  Hotel({
    required this.id,
    required this.groupId,
    required this.name,
    required this.location,
    required this.ownerId,
  });
}

class Room {
  final String id;
  final String number;
  final String status; // Libre, Vendu, Checkout, Service
  final String type; // King, Queen
  final String floor;

  Room({
    required this.id,
    required this.number,
    required this.status,
    required this.type,
    required this.floor,
  });

  int get numberAsInt =>
      int.tryParse(number.replaceAll(RegExp(r'[^0-9]'), '')) ?? 99999;

  Map<String, dynamic> toMap() {
    return {
      'number': number,
      'status': status,
      'type': type,
      'floor': floor,
    };
  }

  factory Room.fromMap(String id, Map<String, dynamic> map) {
    return Room(
      id: id,
      number: map['number'] ?? '',
      status: map['status'] ?? 'Libre',
      type: map['type'] ?? 'King',
      floor: map['floor'] ?? 'General',
    );
  }
}

class Task {
  final String id;
  final String roomId;
  final String title;
  final String description;
  final String assignedRole;
  bool isCompleted;
  final DateTime timestamp;

  Task({
    required this.id,
    required this.roomId,
    required this.title,
    required this.description,
    required this.assignedRole,
    this.isCompleted = false,
    required this.timestamp,
  });
}
