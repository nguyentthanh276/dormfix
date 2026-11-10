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

## Phần 1 — Yêu cầu Sinh viên DF-007–010 — 10/11/2026

- Đã áp dụng `20261109165740_student_request_foundation.sql` qua Supabase migration API lên project `nxobutgnhceyabjbiiya`. Migration được tạo bằng Supabase CLI; bổ sung fingerprint tạo yêu cầu, bốn RPC Sinh viên và ba policy Storage cho ảnh tạm chính chủ. Không đổi mật khẩu, trạng thái hay nội dung yêu cầu có sẵn.
- Trước triển khai, migration cùng `tests/student_request_foundation.sql` chạy trong một transaction rollback, đạt PASS. Sau triển khai, regression độc lập đạt PASS; không còn Auth user `@student-request-test.invalid`. Kiểm thử gồm role/password gate, chính chủ, phòng cũ/snapshot, nhiều vòng xử lý, metadata ảnh, giới hạn ảnh, gửi lặp và giữ nguyên ảnh đã gửi.
- Xác minh catalog: bốn RPC pin `search_path` rỗng, anon không được EXECUTE, authenticated chỉ gọi API có kiểm tra role/tài khoản/quyền; helper không được cấp EXECUTE cho client. Không cấp INSERT trực tiếp lên `repair_requests` hoặc `request_attachments`. Bucket `repair-images` vẫn private, giới hạn 5 MiB và JPEG/PNG/WebP.
- Kiểm tra HTTP với đăng nhập thật: Sinh viên upload PNG, tạo `DF000280`, gửi lại cùng UUID không tạo trùng, đọc danh sách/chi tiết/ảnh; Admin đọc được cùng yêu cầu và ảnh, tải ảnh không có phiên bị từ chối.
- Kiểm tra bằng Supabase Dart SDK và chính `SupabaseRequestRepository`: upload/tạo `DF000285`, thử lại cùng payload, tải ảnh private; `SupabaseAdminRequestRepository` đọc được cùng chi tiết và ảnh. Hai yêu cầu có tiền tố `[DF007 DEMO]` / `[DF007 SDK DEMO]` được giữ để demo. Ảnh kiểm thử là PNG nhỏ, không phải ảnh chụp sự cố thực tế. Test live chỉ chạy thủ công và không được đưa vào CI để tránh ghi dữ liệu dùng chung.
- `dart format`: không còn thay đổi; `flutter analyze`: không có vấn đề; toàn bộ **489 test Flutter đạt**; build web release và Android debug đạt. Đã cài/mở bản Android mới trên `emulator-5554`, khởi tạo Supabase thành công, log khởi động không có lỗi Flutter. Kiểm thử tương tác giao diện dùng widget test; kiểm tra nghiệp vụ thật dùng HTTP/SDK như trên, chưa nghiệm thu chọn ảnh trên máy ảo. Hợp đồng và kịch bản demo tại `../docs/student-requests-contract.md`.
- Security advisor giữ nguyên hai loại cảnh báo đã có: [RPC SECURITY DEFINER được authenticated gọi](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) và [leaked password protection đang tắt](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Không thay cấu hình Auth trong migration này.
- Giới hạn: SQL dùng role/JWT mô phỏng; HTTP/SDK bổ sung kiểm tra phiên thật nhưng chưa kiểm thử giao dịch đồng thời nhiều phiên, mất kết nối thiết bị ở mọi thời điểm hoặc thao tác chọn ảnh trên mọi dòng máy. Phần 1 không triển khai sửa/hủy/xác nhận/sửa lại/mở lại yêu cầu; các nút đó được ẩn trong repository thật. Luồng liên vai trò hoàn chỉnh cần nghiệm thu trong Phần 2.

## Phần 2 — Xác nhận/sửa lại DF-013/014/015 — 10/11/2026

- Đã áp dụng `20261109173649_student_result_confirmation.sql` qua Supabase migration API lên project `nxobutgnhceyabjbiiya`. Thêm `request_history.student_action_fingerprint`, hai RPC `student_confirm_result` / `student_request_rework`, helper riêng và ba policy ảnh phản hồi. Không cấp quyền UPDATE `repair_requests` hoặc INSERT `request_feedback` trực tiếp cho client.
- Migration cùng `tests/student_result_confirmation.sql` đạt PASS trong giao dịch rollback trước triển khai; regression độc lập sau triển khai cũng đạt PASS. Fixture ngẫu nhiên không có mật khẩu, không thay tài khoản/yêu cầu thật và không còn Auth user `@student-confirmation-test.invalid` sau kiểm tra.
- Regression kiểm tra role/password gate/chính chủ, phiên bản cũ, kết quả thiếu/sai phân công/sai phiên bản, xác nhận phòng cũ, metadata/owner/MIME/size/quota năm ảnh, cleanup ảnh tạm và giữ ảnh đã gửi. Replay sau vòng xử lý tiếp theo vẫn trả biên nhận gốc mà không đổi trạng thái hiện tại, thêm lịch sử, feedback hoặc thông báo. Kết quả legacy thiếu request_version chỉ được nhận khi thuộc đúng phân công hiện tại.
- Xác minh catalog sau triển khai: hai RPC public có `search_path` rỗng, anon không được EXECUTE, authenticated được gọi và kiểm tra quyền trong hàm; parser/readiness/resolver riêng không được cấp EXECUTE cho client. Có đúng một cột fingerprint và ba policy mới; bucket tiếp tục private.
- Kiểm tra HTTP thật đã tạo `DF000287`: Admin phân công, KTV bắt đầu và gửi kết quả/ảnh; Sinh viên và Admin đọc cùng kết quả. Giữ yêu cầu này ở Chờ xác nhận để demo tương tác.
- Kiểm tra `app/tool/phase2_live_smoke_test.dart` qua Supabase Dart SDK và chính repository ứng dụng đạt PASS: tạo `DF000297`, Admin phân công, KTV gửi kết quả vòng 1, Sinh viên sửa lại kèm ảnh private, KTV đọc phản hồi/ảnh và nhận đúng một thông báo, tiếp tục/gửi kết quả vòng 2, Sinh viên xác nhận Hoàn tất. Admin đọc được ảnh phản hồi; Sinh viên có hai thông báo kết quả và đánh dấu đã đọc thành công. Replay của hai hành động không tạo trùng; màn hình dùng phiên bản cũ bị từ chối.
- Công cụ SDK chỉ chạy khi bật `DORMFIX_RUN_LIVE_DEMO=1` và cung cấp mật khẩu qua biến môi trường; không nằm trong bộ test CI mặc định. Yêu cầu demo được giữ lại, ảnh dùng PNG kiểm thử nhỏ, không phải ảnh chụp sự cố thực tế. Các phiên Auth do công cụ tạo đều đăng xuất cục bộ khi kết thúc.
- Xác minh Flutter: **531 test tự động đạt**, analyzer không có vấn đề; thêm một kiểm tra SDK live đạt. Android debug và Web release build thành công; bản Android mới đã cài/mở trên `emulator-5554` và khởi tạo Supabase thành công, không có lỗi Flutter trong log khởi động.
- Security advisor vẫn có hai loại cảnh báo nền: [SECURITY DEFINER được authenticated gọi](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) tăng từ 35 lên 40 function do hai API và ba helper policy chủ ý công khai; [leaked password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) vẫn tắt. Không đổi cấu hình Auth trong đợt này.
- Giới hạn: chưa kiểm thử giao dịch nhiều phiên đồng thời, mọi tình huống mất mạng thiết bị hoặc chọn ảnh trực tiếp trên điện thoại thật. Widget test kiểm tra form ở 320px, dirty back, double tap, sai biên nhận, thử lại, đổi tài khoản và quyền khi trở lại từ nền; không thay thế kiểm tra phần cứng. Sửa/hủy/mở lại yêu cầu và mọi nguồn thông báo chưa thuộc phạm vi hoàn thành. Hướng dẫn luồng code và demo tại `../docs/student-result-actions-contract.md`.

## Phần 3 — Sửa, hủy và mở lại DF-011/012/016 — 10/11/2026

- Đã áp dụng migration lên project DormFix `nxobutgnhceyabjbiiya`. Kiểm thử SQL đạt trước và sau triển khai trong giao dịch rollback. Đã xác minh một bản ghi migration, ba policy Storage mới và không có tài khoản fixture SQL còn lại. [Migration](20261109175550_student_request_lifecycle.sql) · [Kiểm thử SQL](tests/student_request_lifecycle.sql)
- Kiểm thử API với ba tài khoản demo tạo `DF000321` để sửa nội dung, giữ/bỏ/thêm ảnh, rồi phân công và hủy. KTV nhận đúng một thông báo. `DF000322` đi qua phân công, xử lý, hoàn tất rồi mở lại về Chờ tiếp nhận với cùng mã, kết quả và lịch sử. Ảnh phản hồi được kiểm tra bằng phiên Sinh viên, Admin và KTV cũ. Gửi lại cùng mã thao tác không tạo thêm lịch sử hay phản hồi. Hai yêu cầu demo được giữ lại và ba phiên kiểm thử đã đăng xuất.
- Đã xác nhận ba RPC dành cho authenticated, helper xử lý riêng không cấp quyền gọi cho client, bucket ảnh vẫn riêng tư và client không có quyền UPDATE trực tiếp bảng yêu cầu. Security Advisor ghi nhận sáu mục mới do ba RPC và ba hàm hỗ trợ policy Storage có quyền EXECUTE theo thiết kế. Cấu hình bảo vệ mật khẩu bị lộ giữ nguyên. [Cảnh báo SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) · [Bảo vệ mật khẩu bị lộ](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
- Bản Phần 3 đạt 545 test Flutter. Hai thứ tự tranh chấp giữa Sinh viên hủy và KTV bắt đầu đều đạt trên PostgreSQL cục bộ. Bản Android mới đã build, cài và mở trên `emulator-5554`, khởi tạo Supabase thành công.

## Phần 4 — Thông báo Sinh viên DF-017 — 10/11/2026

- Đã áp dụng migration lên project DormFix `nxobutgnhceyabjbiiya`. Kiểm thử rollback trên Supabase đạt trước và sau triển khai. Các bài SQL cũ của Admin, KTV và đánh dấu thông báo đã đọc cũng đạt. [Migration](20261109184537_student_notification_events.sql) · [Kiểm thử SQL](tests/student_notification_events.sql)
- Kiểm tra bằng Flutter SDK và ba tài khoản demo. Sinh viên nhận một thông báo phân công `DF000338` và một thông báo từ chối `DF000339`. Cả hai dẫn tới đúng yêu cầu. Số chưa đọc tăng hai rồi giảm một khi đọc mục phân công. KTV nhận đúng thông báo phân công. Mục từ chối được giữ ở trạng thái chưa đọc để thử. Đánh dấu tất cả đã đọc được kiểm tra trên fixture rollback và bằng widget test.
- Hàm trigger không cấp EXECUTE cho anon hoặc authenticated. RLS và quyền ghi bảng giữ nguyên. Security Advisor có cùng các mục cảnh báo như trước khi triển khai. [Cảnh báo SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) · [Bảo vệ mật khẩu bị lộ](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
- Analyzer sạch và 546 test Flutter đạt. Bản Android có số chưa đọc trên tab Thông báo đã build, cài và mở trên `emulator-5554`.

## Phần 5 — Quản lý phòng và loại sự cố DF-039–042/049–050 — 10/11/2026

- Đã áp dụng migration lên project DormFix `nxobutgnhceyabjbiiya`. Kiểm thử rollback trên Supabase đạt trước và sau triển khai. Bộ kiểm tra bao gồm phân quyền, mã/tên trùng, Sinh viên đang hoạt động hoặc bị khóa chặn ngừng phòng, Sinh viên đã thu hồi không chặn, lịch sử thao tác và tên phòng/loại trên yêu cầu đã lưu. Không còn tài khoản fixture SQL. [Migration](20261109185257_admin_rooms_and_categories.sql) · [Kiểm thử SQL](tests/admin_rooms_and_categories.sql)
- Kiểm tra bằng Flutter SDK và tài khoản demo thật. Admin tạo, sửa và ngừng phòng trống `DEMO-P5-71D3BBD2-B`. Sinh viên nhìn thấy loại mới, thấy tên cập nhật khi Admin đổi tên, không chọn được khi loại ngừng hoạt động và chọn được sau khi kích hoạt lại. `DF000362` giữ tên loại lúc tạo. Phòng và loại demo kết thúc ở trạng thái ngừng sử dụng. Ghi nhận ba mục lịch sử phòng và năm mục lịch sử loại cho các thao tác thật. Hai phiên kiểm thử đã đăng xuất.
- Kiểm tra catalog xác nhận tám RPC cho authenticated với kiểm tra Admin trong hàm, anon không được gọi, và client không có quyền ghi trực tiếp vào hai bảng. Security Advisor báo thêm tám mục cho các RPC mới. Cấu hình bảo vệ mật khẩu bị lộ giữ nguyên. [Cảnh báo SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) · [Bảo vệ mật khẩu bị lộ](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
- Analyzer sạch và 556 test Flutter đạt. Bản Android Phần 5 đã build, cài và mở trên `emulator-5554`.

## Phần 6 — Tạo và cập nhật tài khoản DF-031–034 — 10/11/2026

- Đã áp dụng SQL lên DormFix `nxobutgnhceyabjbiiya` với phiên bản ghi trên Supabase `20261109193519`. Edge Function `admin-create-account` phiên bản 1 đang hoạt động và bật xác minh JWT. Tài khoản Auth, hồ sơ DormFix và lịch sử tạo được ghi trong cùng giao dịch Auth. [Migration](20261109191056_admin_account_provisioning.sql) · [Kiểm thử SQL](tests/admin_account_provisioning.sql)
- Kiểm thử SQL rollback đạt trước và sau triển khai. Kiểm thử Flutter SDK trên Supabase tạo và sửa được cả hai vai trò, chặn tạo trùng và chặn bỏ qua bước đổi mật khẩu. Sinh viên đăng nhập lại được với mật khẩu mới và thấy đúng phòng. Kỹ thuật viên được tạo không gắn phòng. Bốn phiên kiểm thử đã đăng xuất, hai tài khoản thử và lịch sử phát sinh đã được dọn.
- Security Advisor ghi nhận 59 RPC SECURITY DEFINER gọi được bởi authenticated, tăng 5 do các RPC mới đã qua kiểm tra quyền. Hai bảng riêng bật RLS, không có quyền truy cập từ client và không có policy mở quyền. Cảnh báo bảo vệ mật khẩu bị lộ vẫn còn. [SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) · [RLS không có policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) · [Bảo vệ mật khẩu bị lộ](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
- Analyzer sạch, 569 test Flutter và 4 test Edge Function đạt. Bản Android đã build, cài và mở trên `emulator-5554`.

## Phần 7 — Quản lý trạng thái và mật khẩu tạm DF-035–038 — 10/11/2026

- Supabase DormFix ghi nhận migration `20261109195434`. Edge Function `admin-reset-account-password` phiên bản 1 đang hoạt động với xác minh JWT. Data API kiểm tra phiên bằng hook trước khi chạy RPC. Bucket ảnh riêng áp dụng điều kiện phiên qua một policy hạn chế. [Migration](20261109194250_admin_account_lifecycle.sql) · [Kiểm thử SQL](tests/admin_account_lifecycle.sql)
- Kiểm thử PostgreSQL local có rollback xác minh chặn khóa/thu hồi Kỹ thuật viên còn việc, cho thu hồi Sinh viên còn yêu cầu, kiểm tra phòng khi khôi phục, lịch sử thao tác và chặn phiên cũ. Kiểm thử Flutter SDK trên Supabase đi qua đủ năm thao tác cho cả hai vai trò. Phiên cũ vẫn bị từ chối sau mở khóa, khôi phục hoặc đặt lại mật khẩu. Sinh viên đăng nhập được bằng mật khẩu mới sau khi hoàn tất đổi mật khẩu tạm. Đã đóng tám phiên thử.
- Analyzer sạch, 576 test Flutter và 5 test Edge Function đặt lại mật khẩu đạt. Đã build, cài và mở bản Android trên `emulator-5554`.
- Security Advisor có thêm bốn RPC SECURITY DEFINER được authenticated gọi và hai bảng riêng bật RLS với quyền client đã thu hồi. Cảnh báo bảo vệ mật khẩu bị lộ vẫn còn. [SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) · [RLS không có policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) · [Bảo vệ mật khẩu bị lộ](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)

## Phần 8 — Nghiệm thu yêu cầu Admin DF-043–048 — 10/11/2026

- Dùng các RPC hiện có của migration 010–012. Flutter tải lại lựa chọn lọc sau khi quay về từ chi tiết hoặc kéo làm mới, giữ lựa chọn còn hợp lệ và bỏ qua kết quả về trễ. Hộp thoại nhập lý do có thể cuộn khi bàn phím mở. Kỹ thuật viên thấy lý do Admin yêu cầu sửa lại ngay trước nút Tiếp tục xử lý.
- Kiểm thử Flutter SDK với Supabase đạt cho danh sách, bộ lọc kết hợp, chi tiết, phân công, từ chối có lý do, đổi Kỹ thuật viên và cả hai thao tác xử lý thay. Kỹ thuật viên cũ mất quyền đọc chi tiết. Người mới cần xác nhận trước khi gửi kết quả. Máy chủ chặn Admin xử lý thay khi Sinh viên chỉ bị khóa hoặc đã khôi phục.
- Trên Android, Admin phân công, đổi Kỹ thuật viên, lọc theo người mới và từ chối có lý do. Kỹ thuật viên mới xác nhận tiếp tục. Admin yêu cầu sửa lại thay Sinh viên đã thu hồi. Kỹ thuật viên đọc lý do và gửi kết quả lần hai. Admin xác nhận hoàn tất. Kiểm tra database thấy đúng hai kết quả, người được giao vẫn là Kỹ thuật viên mới và có đủ hai mục lịch sử xử lý thay.
- Đã dọn sáu tài khoản và bốn yêu cầu có nhãn riêng của hai lượt kiểm thử. Analyzer sạch và 581 test Flutter đạt. Bản APK debug đã build và cài trên `emulator-5554`.
