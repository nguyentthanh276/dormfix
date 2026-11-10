import 'managed_account.dart';

enum AccountLifecycleAction {
  lock(AccountStatus.locked),
  unlock(AccountStatus.active),
  revoke(AccountStatus.revoked),
  restore(AccountStatus.active);

  const AccountLifecycleAction(this.resultingStatus);

  final AccountStatus resultingStatus;
}
