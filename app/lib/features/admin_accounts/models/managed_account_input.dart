import '../../../core/models/app_role.dart';

/// The temporary password is sent to the provisioning function only.
final class CreateManagedAccount {
  const CreateManagedAccount({
    required this.role,
    required this.identityCode,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.temporaryPassword,
    this.roomId,
  });

  final AppRole role;
  final String identityCode;
  final String fullName;
  final String email;
  final String phone;
  final String temporaryPassword;
  final String? roomId;
}

/// Only the mutable profile fields are sent when updating an account.
final class UpdateManagedAccount {
  const UpdateManagedAccount({
    required this.id,
    required this.fullName,
    required this.phone,
    this.roomId,
  });

  final String id;
  final String fullName;
  final String phone;
  final String? roomId;
}
