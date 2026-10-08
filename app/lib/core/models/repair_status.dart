enum RepairStatus {
  pending('pending', 'Chờ tiếp nhận'),
  assigned('assigned', 'Đã phân công'),
  inProgress('in_progress', 'Đang xử lý'),
  awaitingConfirmation('awaiting_confirmation', 'Chờ xác nhận'),
  awaitingRework('awaiting_rework', 'Chờ xử lý lại'),
  completed('completed', 'Hoàn tất'),
  rejected('rejected', 'Từ chối'),
  cancelled('cancelled', 'Đã hủy');

  const RepairStatus(this.databaseValue, this.label);
  final String databaseValue;
  final String label;
}
