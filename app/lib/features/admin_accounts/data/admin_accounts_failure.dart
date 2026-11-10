class AdminAccountsFailure implements Exception {
  const AdminAccountsFailure(
    this.message, {
    this.accessDenied = false,
    this.conflict = false,
    this.uncertain = false,
  });

  final String message;
  final bool accessDenied;
  final bool conflict;
  final bool uncertain;

  @override
  String toString() => message;
}
