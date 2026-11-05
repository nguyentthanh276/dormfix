import '../../../core/models/app_role.dart';

enum AccountStatus {
  active('active', 'Đang hoạt động'),
  locked('locked', 'Bị khóa'),
  revoked('revoked', 'Đã thu hồi');

  const AccountStatus(this.databaseValue, this.label);
  final String databaseValue;
  final String label;
}

class ManagedAccount {
  const ManagedAccount({
    required this.fullName,
    required this.identityCode,
    required this.role,
    required this.status,
  });

  factory ManagedAccount.fromJson(Map<String, dynamic> json) {
    final role = AppRole.values.where(
      (item) => item.databaseValue == json['role'] && item != AppRole.admin,
    );
    final status = AccountStatus.values.where(
      (item) => item.databaseValue == json['status'],
    );
    if (json['full_name'] is! String ||
        json['identity_code'] is! String ||
        role.isEmpty ||
        status.isEmpty) {
      throw const FormatException('Dữ liệu tài khoản không hợp lệ.');
    }
    return ManagedAccount(
      fullName: json['full_name'] as String,
      identityCode: json['identity_code'] as String,
      role: role.first,
      status: status.first,
    );
  }

  final String fullName;
  final String identityCode;
  final AppRole role;
  final AccountStatus status;
}

/// Kết quả sau khi Admin tạo tài khoản Sinh viên thành công (DF-031).
class CreatedStudentResult {
  const CreatedStudentResult({
    required this.id,
    required this.identityCode,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    required this.mustChangePassword,
    required this.temporaryPassword,
    required this.roomId,
    this.roomCode,
    this.roomBuilding,
  });

  factory CreatedStudentResult.fromJson(Map<String, dynamic> json) {
    final roomMap = json['room'] as Map<String, dynamic>?;
    return CreatedStudentResult(
      id: json['id'] as String,
      identityCode: json['identity_code'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String,
      role: json['role'] as String? ?? 'student',
      status: json['status'] as String? ?? 'active',
      mustChangePassword: json['must_change_password'] == true,
      temporaryPassword: json['temporary_password'] as String,
      roomId: roomMap?['id'] as String? ?? json['room_id'] as String? ?? '',
      roomCode: roomMap?['code'] as String?,
      roomBuilding: roomMap?['building'] as String?,
    );
  }

  final String id;
  final String identityCode;
  final String fullName;
  final String email;
  final String phone;
  final String role;
  final String status;
  final bool mustChangePassword;
  final String temporaryPassword;
  final String roomId;
  final String? roomCode;
  final String? roomBuilding;
}

class CreatedTechnicianResult {
  const CreatedTechnicianResult({
    required this.id,
    required this.identityCode,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.status,
    required this.mustChangePassword,
    required this.temporaryPassword,
  });

  factory CreatedTechnicianResult.fromJson(Map<String, dynamic> json) =>
      CreatedTechnicianResult(
        id: json['id'] as String,
        identityCode: json['identity_code'] as String,
        fullName: json['full_name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String,
        status: json['status'] as String? ?? 'active',
        mustChangePassword: json['must_change_password'] == true,
        temporaryPassword: json['temporary_password'] as String,
      );

  final String id;
  final String identityCode;
  final String fullName;
  final String email;
  final String phone;
  final String status;
  final bool mustChangePassword;
  final String temporaryPassword;
}

class StudentAccountEditDetails {
  const StudentAccountEditDetails({
    required this.fullName,
    required this.phone,
    required this.roomId,
    required this.roomCode,
    required this.roomBuilding,
  });

  factory StudentAccountEditDetails.fromJson(Map<String, dynamic> json) {
    final room = json['room'] as Map<String, dynamic>?;
    return StudentAccountEditDetails(
      fullName: json['full_name'] as String,
      phone: json['phone'] as String,
      roomId: room?['id'] as String? ?? '',
      roomCode: room?['code'] as String? ?? '',
      roomBuilding: room?['building'] as String? ?? '',
    );
  }

  final String fullName;
  final String phone;
  final String roomId;
  final String roomCode;
  final String roomBuilding;
}

class ResetPasswordResult {
  const ResetPasswordResult({
    required this.id,
    required this.identityCode,
    required this.fullName,
    required this.role,
    required this.status,
    required this.mustChangePassword,
    required this.temporaryPassword,
  });

  factory ResetPasswordResult.fromJson(Map<String, dynamic> json) =>
      ResetPasswordResult(
        id: json['id'] as String,
        identityCode: json['identity_code'] as String,
        fullName: json['full_name'] as String,
        role: json['role'] as String,
        status: json['status'] as String,
        mustChangePassword: json['must_change_password'] == true,
        temporaryPassword: json['temporary_password'] as String,
      );

  final String id;
  final String identityCode;
  final String fullName;
  final String role;
  final String status;
  final bool mustChangePassword;
  final String temporaryPassword;
}
