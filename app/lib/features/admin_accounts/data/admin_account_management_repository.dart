import '../models/managed_account.dart';
import '../models/managed_account_input.dart';

export 'admin_accounts_failure.dart';

abstract interface class AdminAccountManagementRepository {
  Future<ManagedAccountDetails> fetchDetails(String identityCode);
  Future<ManagedAccountDetails> createAccount(CreateManagedAccount input);
  Future<ManagedAccountDetails> updateAccount(UpdateManagedAccount input);
}
