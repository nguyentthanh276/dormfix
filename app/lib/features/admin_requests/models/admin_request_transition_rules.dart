import '../../../core/models/repair_status.dart';

enum AdminRequestAdminAction { assign, reject }

class AdminRequestTransitionRules {
  const AdminRequestTransitionRules._();

  // DF-045/046: write RPCs enforce these rules again under row locks.
  static bool allows(AdminRequestAdminAction action, RepairStatus status) =>
      (action == AdminRequestAdminAction.assign ||
          action == AdminRequestAdminAction.reject) &&
      status == RepairStatus.pending;
}
