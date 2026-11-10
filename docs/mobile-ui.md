# Khung giao diện điện thoại DormFix

Phạm vi Phần 0: khung điều hướng và thành phần giao diện chung đã chốt ngày
09/11/2026. Dữ liệu và quyền nghiệp vụ giữ nguyên để triển khai từng phần sau.

## Điều hướng theo vai trò

| Vai trò | Bốn tab |
| --- | --- |
| Sinh viên | Yêu cầu · Chờ xác nhận · Thông báo · Cá nhân |
| Kỹ thuật viên | Công việc · Lịch sử · Thông báo · Cá nhân |
| Admin | Yêu cầu · Tài khoản · Phòng · Loại sự cố |

Màn hình gốc có header cam đậm, tiêu đề, nhãn vai trò và avatar. Avatar của
Sinh viên/KTV mở tab Cá nhân. Avatar Admin mở thông tin tài khoản và Đăng xuất;
không thêm chức năng sửa hồ sơ Admin. Đăng xuất SV/KTV nằm trong Cá nhân.

Tạo yêu cầu là nút trong danh sách, mở trang riêng. Các trang chi tiết và biểu mẫu
ẩn thanh tab. Quay lại trả về đúng tab, bộ lọc và vị trí danh sách. Các tab được
khởi tạo khi mở lần đầu và giữ trạng thái trong cùng một phiên đăng nhập.

## Luồng code

- `app/lib/core/widgets/dormfix_app_bar.dart`: header dùng chung và avatar.
- `app/lib/core/widgets/role_navigation_bar.dart`: thanh điều hướng dùng chung.
- `app/lib/core/theme/`: màu, kiểu chữ, nút, ô nhập, nhãn trạng thái.
- `app/lib/app/startup_page.dart`: chọn Home theo vai trò và ID người dùng.
- `app/lib/features/student_requests/presentation/student_shell_screen.dart`:
  bốn tab Sinh viên, tạo yêu cầu và cập nhật khi trở lại tab.
- `app/lib/features/admin_requests/presentation/admin_home_page.dart`:
  bốn tab Admin và menu tài khoản.
- `app/lib/features/technician_jobs/presentation/technician_home_page.dart`:
  bốn tab KTV, chi tiết công việc và quay lại tab nguồn.
- `app/lib/features/profile/presentation/profile_page.dart`: hồ sơ nhúng trong
  tab Cá nhân; đổi mật khẩu mở trang riêng.

Mỗi Home sở hữu vùng điều hướng của mình. Đăng xuất hoặc đổi danh tính hủy cả
vùng này, gồm chi tiết, ảnh và các biểu mẫu đang mở. Phản hồi hồ sơ cũ không được
cập nhật hay đăng xuất tài khoản mới. Biểu mẫu tạo yêu cầu và đổi mật khẩu hỏi
trước khi bỏ nội dung chưa gửi.

## Demo Phần 0

1. Đăng nhập Sinh viên. Kiểm tra bốn tab, avatar, bộ lọc và nút Tạo yêu cầu.
2. Chọn một bộ lọc, chuyển sang Thông báo rồi trở lại Yêu cầu. Bộ lọc được giữ.
3. Mở chi tiết hoặc Tạo yêu cầu: thanh tab biến mất. Quay lại về đúng danh sách.
4. Nhập thử biểu mẫu rồi quay lại: có xác nhận bỏ thay đổi.
5. Đăng xuất từ Cá nhân, đăng nhập Admin: thấy bốn tab quản trị và menu avatar.
6. Mở chi tiết yêu cầu Admin rồi quay lại. Kiểm tra tìm kiếm/lọc tài khoản khi
   chuyển qua lại các tab.
7. Đăng nhập KTV, chọn bộ lọc công việc, chuyển Lịch sử/Thông báo/Cá nhân rồi quay
   lại. Mở công việc từ Lịch sử và quay lại đúng Lịch sử.
8. Mở Đổi mật khẩu từ Cá nhân: thanh tab ẩn. Hủy biểu mẫu để trở lại hồ sơ.

## Giới hạn nghiệp vụ hiện có

Phần 0 chỉ nghiệm thu khung giao diện, không đánh dấu các nghiệp vụ còn thiếu là
đã hoàn thành. Sau Phần 0, [Phần 1 DF-007–010](student-requests-contract.md) đã
nối tạo/đọc yêu cầu và adapter thông báo Sinh viên vào Supabase ngày 10/11/2026.
Phần 2 đã bổ sung xác nhận và yêu cầu sửa lại qua Supabase. [Luồng DF-013/014/015](student-result-actions-contract.md)

Phần 3 đã bổ sung sửa, hủy và mở lại. Màn hình chi tiết chỉ hiện những thao tác được máy chủ cho phép trên yêu cầu đang xem. [Migration DF-011/012/016](../database/20261109175550_student_request_lifecycle.sql)

## Xác minh Phần 0 — 09/11/2026

- `dart format --output=none --set-exit-if-changed lib test`: đạt.
- `flutter analyze`: không có vấn đề.
- `flutter test --no-pub`: 449 kiểm thử đạt, gồm điều hướng ba role, màn hình
  320px, giữ bộ lọc/vị trí cuộn, xác nhận bỏ bản nhập và xóa màn hình khi hết phiên.
- Build Android debug và build web theo CI: đạt.
- Đã cài và mở ứng dụng trên máy ảo `PRM393_API36` (`emulator-5554`). Xác minh
  bằng tài khoản đăng nhập thật và dữ liệu Supabase được ghi nhận riêng khi demo;
  các kiểm thử điều hướng sử dụng repository thử nghiệm.
