import '../../../core/models/repair_status.dart';

/// UI visibility rules mirror the authoritative Admin transition RPC guard.
enum AdminRequestAdminAction {
  assign,
  reject,
  transfer,
  confirmForRevokedStudent,
  requestReworkForRevokedStudent,
}

class AdminRequestTransitionRules {
  const AdminRequestTransitionRules._();

  // DF-045/046/047/048: server RPCs enforce these rules again under row locks.
  static bool allows(
    AdminRequestAdminAction action,
    RepairStatus status, {
    String? studentAccountStatus,
  }) => switch (action) {
    AdminRequestAdminAction.assign ||
    AdminRequestAdminAction.reject => status == RepairStatus.pending,
    AdminRequestAdminAction.transfer => {
      RepairStatus.assigned,
      RepairStatus.inProgress,
      RepairStatus.awaitingRework,
    }.contains(status),
    AdminRequestAdminAction.confirmForRevokedStudent ||
    AdminRequestAdminAction.requestReworkForRevokedStudent =>
      status == RepairStatus.awaitingConfirmation &&
          studentAccountStatus == 'revoked',
  };
}
