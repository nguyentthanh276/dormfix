import '../models/account_lifecycle_action.dart';
import '../models/managed_account.dart';

export 'admin_accounts_failure.dart';

abstract interface class AdminAccountLifecycleRepository {
  Future<ManagedAccountDetails> changeAccountStatus({
    required String accountId,
    required AccountStatus expectedStatus,
    required AccountLifecycleAction action,
    String? reason,
    String? roomId,
  });

  Future<ManagedAccountDetails> resetTemporaryPassword({
    required String accountId,
    required AccountStatus expectedStatus,
    required String temporaryPassword,
  });
}
