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

## Đánh dấu thông báo Sinh viên đã đọc — 03/11/2026

- Đã áp dụng `014_student_notification_reads.sql` qua Supabase migration API trên project `nxobutgnhceyabjbiiya`, sau xác nhận của người dùng. Migration bổ sung `student_mark_notification_read(uuid)` và `student_mark_all_notifications_read()` cùng helper nội bộ.
- Migration và `tests/014_student_notification_reads.sql` đạt PASS trong transaction rollback trước triển khai; regression chạy lại sau triển khai cũng đạt PASS. Không còn Auth user `@student-notification-test.invalid`.
- Cả ba function pin `search_path` rỗng. Anon không được EXECUTE; helper không được cấp EXECUTE cho authenticated. Hai RPC kiểm tra Sinh viên active/đã đổi mật khẩu, khóa chia sẻ profile và chỉ đổi `read_at` của chính người nhận; client vẫn không có UPDATE trên bảng `notifications`.
- Security advisor tiếp tục báo nhóm SECURITY DEFINER RPC chủ ý công khai và cấu hình Auth đã ghi ở mục 013; kiểm tra SQL xác minh role/quyền sở hữu/ACL. Chưa nối adapter Supabase vào luồng Sinh viên đang dùng mock; kiểm thử SQL/JWT mô phỏng và HTTP mock không thay thế đăng nhập thật hoặc giao dịch song song.

## Tạo tài khoản Kỹ thuật viên — DF-032

- Migration mới `016_admin_create_technician.sql` phụ thuộc helper Admin trong migration 015; cần xác minh trạng thái 015 trên project dùng chung trước khi áp dụng theo thứ tự.
- Chưa có xác nhận triển khai 016 hoặc chạy `tests/016_admin_create_technician.sql` trên project Supabase. Migration chỉ được áp dụng sau khi trạng thái hiện tại đã kiểm tra để tránh chạy lại migration đã có.
- Ứng dụng không cung cấp luồng đăng ký công khai. Nếu project không cho phép Auth self-signup, kiểm tra và tắt `Allow new users to sign up` trong Supabase Auth settings; migration SQL không thay đổi cấu hình Auth của project.

## Cập nhật Sinh viên — DF-033

- Migration mới `017_admin_update_student.sql` bổ sung RPC Admin đọc dữ liệu form và cập nhật tên, điện thoại, phòng; áp dụng sau 016.
- Chưa xác nhận triển khai 017 hoặc chạy `tests/017_admin_update_student.sql` trên project Supabase. Migration chỉ cập nhật `profiles`, không chỉnh sửa yêu cầu/snapshot cũ.
- Backend tạo request Sinh viên và repository Flutter hiện vẫn là mock. Khi luồng tạo thật được nối, server phải đọc phòng hiện tại qua `current_student_room()` trong transaction tạo request để request mới dùng phòng mới.

## Thu hồi tài khoản — DF-036

- Migration mới `018_admin_revoke_account.sql` phụ thuộc helper Admin từ 015 và các migration nghiệp vụ đến 017. Chưa xác nhận triển khai 018 hoặc chạy `tests/018_admin_revoke_account.sql` trên project Supabase.
- Khi áp dụng, kiểm tra trạng thái các migration trước và chạy đúng thứ tự; migration thu hồi cập nhật `profiles.status`, `auth.users.banned_until` và `request_history` cùng transaction, không xóa Auth user/profile/request.
- DF-048 đã có các RPC Admin xử lý yêu cầu `awaiting_confirmation` của Sinh viên bị thu hồi; regression DF-036 kiểm tra tiếp tục xử lý xác nhận và yêu cầu sửa lại.

## Khôi phục tài khoản — DF-037

- Migration mới `019_admin_restore_account.sql` phụ thuộc migration 018. Chưa xác nhận triển khai 019 hoặc chạy `tests/019_admin_restore_account.sql` trên project Supabase.
- Student cần được gắn một phòng đang active; Kỹ thuật viên bị từ chối nếu còn bất kỳ request chưa kết thúc. Migration cập nhật Auth ban/profile trong cùng transaction, ghi lịch sử, không tạo lại tài khoản và không chỉnh sửa request/snapshot.
- Sau restore, profile là `active`, nên hai RPC DF-048 không còn cho Admin xác nhận/yêu cầu sửa lại thay. Student confirmation hiện vẫn dùng mock/direct table path chưa được cấp quyền ghi; việc tự xác nhận request thật cần backend Student confirmation được nối trước khi xem luồng này là production-complete.

## Đặt lại mật khẩu — DF-038

- Migration mới `020_admin_reset_account_password.sql` phụ thuộc migration 019. Chưa xác nhận triển khai 020 hoặc chạy `tests/020_admin_reset_account_password.sql` trên project Supabase.
- RPC sinh mật khẩu tạm, chỉ trả plaintext mới cho Admin nhận một lần; database lưu bcrypt hash, không trả hash hoặc mật khẩu cũ. Giữ nguyên account status, đặt `must_change_password=true`, xóa Auth sessions để refresh token cũ không dùng lại.
- JWT access token đã phát hành có thể còn hiệu lực đến khi hết hạn; trong thời gian đó, các nghiệp vụ database vẫn bị chặn bởi cờ `must_change_password`. Frontend hiện hiển thị màn đổi mật khẩu sau khi nạp lại profile.

## Đặt lại mật khẩu — DF-038

- Migration mới `020_admin_reset_account_password.sql` áp dụng sau 019. Chưa xác nhận triển khai 020 hoặc chạy `tests/020_admin_reset_account_password.sql` trên project Supabase.
- RPC chỉ trả mật khẩu tạm plaintext mới cho Admin nhận một lần; database lưu bcrypt hash, bật `must_change_password` và xóa các dòng `auth.sessions` của user để refresh token cũ bị cascade-revoke. Hash/mật khẩu cũ không có trong response.
- Giữ nguyên role/status tài khoản. JWT access token stateless đã phát hành vẫn có thể hợp lệ đến khi hết hạn; các RPC nghiệp vụ phải tiếp tục kiểm tra `must_change_password`.
