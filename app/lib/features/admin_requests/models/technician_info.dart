/// Một kỹ thuật viên hiển thị trong giao diện quản lý (tên, SĐT, số việc đang làm).
class TechnicianInfo {
  const TechnicianInfo({
    required this.id,
    required this.name,
    required this.phone,
    required this.activeJobs,
  });

  final String id;
  final String name;
  final String phone;
  final int activeJobs;
}
