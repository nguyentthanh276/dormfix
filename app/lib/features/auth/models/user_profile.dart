import '../../../core/models/app_role.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.identityCode,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    required this.room,
    required this.mustChangePassword,
    required this.canAccess,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    if (status == 'locked' || status == 'revoked') {
      return UserProfile(
        id: json['id'] is String ? json['id'] as String : '',
        identityCode: null,
        fullName: null,
        email: null,
        phone: null,
        role: null,
        status: status as String,
        room: null,
        mustChangePassword: json['must_change_password'] == true,
        canAccess: json['can_access'] == true,
      );
    }

    if (status != 'active') {
      throw const FormatException('Trạng thái hồ sơ không hợp lệ.');
    }

    final roleValue = json['role'];
    final role = AppRole.values.where(
      (candidate) => candidate.databaseValue == roleValue,
    );
    final id = json['id'];
    final identityCode = json['identity_code'];
    final fullName = json['full_name'];
    final email = json['email'];
    final phone = json['phone'];
    final mustChangePassword = json['must_change_password'];
    final canAccess = json['can_access'];
    final roomValue = json['room'];

    if (role.isEmpty ||
        id is! String ||
        identityCode is! String ||
        fullName is! String ||
        email is! String ||
        (phone != null && phone is! String) ||
        mustChangePassword is! bool ||
        canAccess is! bool ||
        (roomValue != null && roomValue is! Map)) {
      throw const FormatException('Thông tin hồ sơ không đầy đủ.');
    }

    return UserProfile(
      id: id,
      identityCode: identityCode,
      fullName: fullName,
      email: email,
      phone: phone as String?,
      role: role.first,
      status: status,
      room: roomValue == null
          ? null
          : RoomProfile.fromJson(Map<String, dynamic>.from(roomValue)),
      mustChangePassword: mustChangePassword,
      canAccess: canAccess,
    );
  }

  final String id;
  final String? identityCode;
  final String? fullName;
  final String? email;
  final String? phone;
  final AppRole? role;
  final String status;
  final RoomProfile? room;
  final bool mustChangePassword;
  final bool canAccess;
}

class RoomProfile {
  const RoomProfile({
    required this.id,
    required this.code,
    required this.building,
    required this.isActive,
  });

  factory RoomProfile.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final code = json['code'];
    final building = json['building'];
    final isActive = json['is_active'];
    if (id is! String ||
        code is! String ||
        (building != null && building is! String) ||
        isActive is! bool) {
      throw const FormatException('Thông tin phòng không hợp lệ.');
    }
    return RoomProfile(
      id: id,
      code: code,
      building: building as String?,
      isActive: isActive,
    );
  }

  final String id;
  final String code;
  final String? building;
  final bool isActive;
}
