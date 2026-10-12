# Triển khai schema DormFix

- Ngày xác nhận: 12/10/2026 (Asia/Ho_Chi_Minh).
- Project: DormFix / Group06-PRM393, ID `nxobutgnhceyabjbiiya`.
- Đã kiểm tra trước khi chạy: public có 0 bảng và chưa có 3 enum DormFix.
- Đã chạy schema tương đương `001_schema.sql` trong SQL Editor, transaction báo thành công.
- Xác minh sau chạy: 10 bảng, cả 10 bật RLS, 10 chính sách đọc, 3 hàm hỗ trợ phân quyền.
- Danh mục ban đầu: Điện, Nước, Nội thất, Khác.
- Thời điểm kiểm tra: 0 Auth users, 0 profiles.

Không chạy lại `001_schema.sql` trên project này. Thay đổi tiếp theo dùng migration riêng.

Đây là xác minh cấu trúc và seed dữ liệu; chưa kiểm thử quyền bằng tài khoản từng role, chưa có hàm ghi nghiệp vụ, endpoint hồ sơ đầy đủ hay Storage policies. Tài khoản demo được tạo trong bước tiếp theo, xem cập nhật bên dưới.

## Hồ sơ demo — 12/10/2026

Đã chạy 002_demo_profiles.sql: ADMIN001 / admin@example.com (admin, active, must_change_password=false); SV001 / student@example.com (student, active, must_change_password=true, phòng DEMO-A101); KTV001 / technican@example.com (technician, active, must_change_password=true). Cả ba liên kết đúng Auth user/email và đã xác nhận email. Đây là xác minh dữ liệu, chưa kiểm thử đăng nhập hoặc phân quyền theo phiên người dùng.

## RPC hồ sơ chính chủ — 12/10/2026

Đã triển khai 003_get_my_profile.sql và chạy database/tests/003_get_my_profile.sql. Bộ kiểm thử đạt cho 3 role, anon, thiếu danh tính/hồ sơ, cờ đổi mật khẩu, tài khoản locked/revoked và quyền đọc cột/ghi flag. Test dùng SET LOCAL ROLE và JWT sub mô phỏng trong SQL Editor, rollback mọi thay đổi; chưa phải kiểm thử đăng nhập HTTP/Flutter thực tế.

Chỉ authenticated được gọi get_my_profile(); hàm không nhận user ID. Xem docs/auth-contract.md. Endpoint đổi mật khẩu phía server chưa triển khai.
