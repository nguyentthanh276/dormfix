import '../../../core/models/app_role.dart';

class UserProfile {
  UserProfile.fromRow(Map<String, Object?> row)
    : id = row['id'] as String,
      identityCode = row['identity_code'] as String,
      fullName = row['full_name'] as String,
      email = row['email'] as String,
      phone = row['phone'] as String?,
      role = AppRole.values.firstWhere(
        (role) => role.databaseValue == row['role'],
      ),
      status = row['status'] as String,
      mustChangePassword = row['must_change_password'] == 1,
      roomCode = row['room_code'] as String?;
  final String id, identityCode, fullName, email, status;
  final String? phone, roomCode;
  final AppRole role;
  final bool mustChangePassword;
}
