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
  const ManagedAccount({required this.fullName, required this.identityCode, required this.role, required this.status});

  factory ManagedAccount.fromJson(Map<String, dynamic> json) {
    final role = AppRole.values.where((item) => item.databaseValue == json['role'] && item != AppRole.admin);
    final status = AccountStatus.values.where((item) => item.databaseValue == json['status']);
    if (json['full_name'] is! String || json['identity_code'] is! String || role.isEmpty || status.isEmpty) {
      throw const FormatException('Dữ liệu tài khoản không hợp lệ.');
    }
    return ManagedAccount(fullName: json['full_name'] as String, identityCode: json['identity_code'] as String, role: role.first, status: status.first);
  }

  final String fullName;
  final String identityCode;
  final AppRole role;
  final AccountStatus status;
}
