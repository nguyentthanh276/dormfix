class AdminCatalogFailure implements Exception {
  const AdminCatalogFailure(
    this.message, {
    this.accessDenied = false,
    this.conflict = false,
    this.uncertain = false,
  });

  final String message;
  final bool accessDenied;
  final bool conflict;
  final bool uncertain;

  static const unavailable = AdminCatalogFailure(
    'Chức năng quản lý chưa sẵn sàng. Vui lòng kiểm tra kết nối.',
  );

  @override
  String toString() => message;
}
