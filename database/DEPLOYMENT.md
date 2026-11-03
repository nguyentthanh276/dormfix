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

## Công việc Kỹ thuật viên — 15/10/2026

- Project DormFix: `nxobutgnhceyabjbiiya`; kiểm tra trên SQL Editor của project.
- Trước thay đổi: chưa có hai RPC Kỹ thuật viên; bucket `repair-images` đã private, giới hạn 5,242,880 byte và JPEG/PNG/WebP; chưa có Storage policy. Không có Kỹ thuật viên active đã hoàn tất cờ mật khẩu tạm.
- Đã chạy migration 004 và toàn bộ `tests/004_technician_jobs.sql` trong cùng một transaction, đạt **PASS** rồi rollback. Nội dung SQL chạy khớp file nguồn sau khi bỏ comment/khoảng trắng.
- Bộ test xác minh anon/thiếu danh tính/thiếu profile/sai role, locked/revoked/password gate, tám trạng thái, snapshot phòng/loại, contact, kết quả/phản hồi/ảnh/lịch sử, chuyển giao và quyền Storage metadata. Fixture dùng Auth user tổng hợp không có mật khẩu và đều rollback; sequence mã yêu cầu có thể có khoảng trống như thiết kế.
- Sau đó đã áp dụng `004_technician_jobs.sql` với commit: `technician_list_jobs()` và `technician_get_job(uuid)` tồn tại; policy `repair_images_authorized_read` tồn tại đúng một lần. Xác minh không còn Auth user `@technician-test.invalid`.
- Đã gọi cả hai RPC qua HTTP thật bằng publishable key, không có phiên đăng nhập: cùng trả HTTP 401 với SQLSTATE `42501`, từ chối quyền EXECUTE của anon.
- Migration không đổi tài khoản, mật khẩu, cờ đổi mật khẩu hay yêu cầu có sẵn. Chưa chạy seed demo tùy chọn.
- Giới hạn xác minh: SQL test dùng role/JWT-sub mô phỏng và Storage metadata. Chưa có phiên Kỹ thuật viên đủ điều kiện để kiểm thử toàn bộ Flutter/HTTP bằng tài khoản thật; chưa tải object ảnh thật. Luồng đổi mật khẩu bắt buộc là công việc DF-003 riêng, vẫn cần hoàn thiện.

## Lịch sử và thông báo Kỹ thuật viên — 03/11/2026

- Đã áp dụng `013_technician_tracking.sql` qua Supabase migration API trên project `nxobutgnhceyabjbiiya` sau các migration Admin 011/012 hiện có.
- Trước triển khai, migration và `tests/013_technician_tracking.sql` chạy trong cùng một transaction rồi rollback, đạt PASS. Sau triển khai, chạy lại regression độc lập cũng đạt PASS; không còn Auth user `@technician-tracking-test.invalid`.
- Xác minh có ba RPC `technician_list_work_history`, `technician_list_notifications`, `technician_mark_notification_read` và đúng một trigger `technician_tracking_events`. Các function đều pin `search_path` rỗng; anon không có quyền thực thi, helper trigger không cấp EXECUTE cho authenticated. Ba RPC công khai kiểm tra role/trạng thái/mật khẩu và dữ liệu chính chủ.
- Security advisor báo [các SECURITY DEFINER RPC gọi được bởi authenticated](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), bao gồm ba API mới được chủ ý công khai cho ứng dụng. Quyền chủ sở hữu, role, tài khoản và ACL đã được kiểm tra bằng SQL regression; không cấp quyền ghi bảng thông báo trực tiếp. Advisor cũng nhắc cấu hình [leaked password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) đang tắt trên project; cấu hình Auth không thay đổi trong đợt này.
- Trigger chỉ tạo thông báo từ các thay đổi database mới, không backfill dữ liệu cũ. Các thao tác mock cục bộ không tạo sự kiện trên Supabase. SQL xác minh bằng role/JWT mô phỏng; chưa xác minh thao tác Student qua HTTP thật hoặc giao dịch song song hai phiên. Sequence mã yêu cầu có thể có khoảng trống do fixture rollback.
