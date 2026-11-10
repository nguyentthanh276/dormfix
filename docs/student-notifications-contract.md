# DF-017: thông báo Sinh viên

Migration `database/014_student_notification_reads.sql` bổ sung hai RPC đánh dấu đọc sau migration 013. Đã triển khai lên Supabase DormFix ngày 03/11/2026 và regression rollback đạt PASS trước/sau triển khai; xem `database/DEPLOYMENT.md`. Không chạy lại migration đã áp dụng. Không cấp quyền UPDATE/INSERT/DELETE trực tiếp trên `notifications`, không đổi RPC hoặc trigger Kỹ thuật viên.

## Quyền và lỗi

Hai RPC chỉ cấp EXECUTE cho `authenticated`; mỗi lần gọi vẫn kiểm tra `auth.uid()`, profile role `student`, trạng thái `active` và `must_change_password=false`. Profile được khóa `FOR SHARE` đến hết transaction để thao tác đánh dấu đọc tuần tự với khóa/thu hồi tài khoản hoặc thay cờ mật khẩu. Helper nội bộ không được cấp EXECUTE cho client. Tất cả function dùng `SECURITY DEFINER` với `search_path=''` và tên bảng/hàm có schema.

| SQLSTATE | Mã lỗi | Ý nghĩa |
| --- | --- | --- |
| `28000` | `AUTH_REQUIRED` | Không có UID đăng nhập. |
| `42501` | `STUDENT_ACCESS_DENIED` | Sai role, thiếu profile, tài khoản khóa/thu hồi hoặc chưa đổi mật khẩu. |
| `P0002` | `NOTIFICATION_NOT_FOUND` | ID không tồn tại, null hoặc thuộc người nhận khác; cùng một lỗi cho các trường hợp này. |

## Biên nhận và thời gian

`student_mark_notification_read(p_notification_id uuid)` chỉ tìm thông báo có `recipient_id=auth.uid()`. Trả đúng `{"id":"uuid","read_at":"timestamptz"}`; server đặt thời gian lần đọc đầu tiên, gọi lặp giữ nguyên mốc cũ.

`student_mark_all_notifications_read()` chỉ đổi các thông báo chính chủ đang có `read_at IS NULL`. Trả đúng `{"updated_count":2,"read_at":"timestamptz"}`; mọi hàng được đổi trong lần gọi dùng chung thời gian server. Hàng đã đọc giữ nguyên thời gian cũ. Inbox rỗng hoặc gọi lại trả `updated_count=0`; `read_at` trong biên nhận là thời gian của thao tác hiện tại, kể cả khi không có hàng nào thay đổi.

Client không truyền người nhận, thời gian đọc, nội dung hoặc loại sự kiện. Thao tác không thay nội dung thông báo, yêu cầu, lịch sử hoặc quyền mở chi tiết.

## Adapter và phạm vi tích hợp

`SupabaseNotificationRepository` đọc bảng bằng JWT của phiên hiện tại, lọc `recipient_id`, sắp xếp `created_at DESC, id DESC`; RLS hiện có tiếp tục kiểm tra người nhận và tài khoản đang active/đã đổi mật khẩu. Đếm chưa đọc dùng cùng bộ lọc với `read_at IS NULL`. Hai lệnh ghi gọi RPC và chỉ hoàn thành sau khi kiểm tra cấu trúc biên nhận, ID tương ứng và timestamp có múi giờ.

Mọi thao tác kiểm tra phiên còn hạn trước/sau request. Đổi tài khoản hoặc đăng xuất trong khi chờ phản hồi làm kết quả cũ bị loại bỏ, kể cả khi quay lại tài khoản ban đầu; refresh token cùng tài khoản vẫn hợp lệ. Lỗi SQL/HTTP/transport được chuyển thành thông báo an toàn; không hiển thị payload, thông tin SQL hoặc token.

`DormFixApp` truyền `SupabaseNotificationRepository` và `SupabaseRequestRepository` xuống `StudentHomePage`. Bấm thông báo đánh dấu mục đó đã đọc rồi tải chi tiết theo UUID để máy chủ kiểm tra quyền. Tab Thông báo hiển thị số chưa đọc từ Supabase và cập nhật khi tải lại hộp thư, đánh dấu đã đọc hoặc quay lại ứng dụng.

Phần 4 đã triển khai ngày 10/11/2026. Khi Admin chuyển yêu cầu từ Chờ tiếp nhận sang Đã phân công hoặc Từ chối, trigger tạo một thông báo `assigned` hoặc `rejected` cho Sinh viên sở hữu yêu cầu trong cùng giao dịch. Thông báo chứa nội dung chung. Lý do từ chối nằm trong chi tiết yêu cầu. Chuyển giao KTV và cập nhật không đổi trạng thái không tạo thêm thông báo phân công. Dữ liệu cũ giữ nguyên. [Migration sự kiện](../database/20261109184537_student_notification_events.sql)

Phần 2 đã kiểm tra bằng SDK thật các thông báo `repair_reported` từ hai vòng gửi kết quả. Phần 4 kiểm tra thông báo phân công cho `DF000338` và từ chối cho `DF000339`. Cả hai mở đúng yêu cầu. Đánh dấu một mục đã đọc làm số chưa đọc giảm một và lần gọi lại giữ nguyên thời điểm đọc. [Kết quả triển khai](../database/DEPLOYMENT.md)

## Kiểm thử

`database/tests/014_student_notification_reads.sql` dùng Auth user tổng hợp không có mật khẩu/phiên, mô phỏng role/JWT và kết thúc bằng ROLLBACK. Kiểm tra ACL, role/trạng thái/mật khẩu, inbox rỗng, chỉ người nhận, timestamp server, gọi lặp, giữ nguyên thời gian cũ/nội dung và chặn ghi trực tiếp. Không thay tài khoản hoặc yêu cầu demo có sẵn. Kiểm thử song song hai session và đăng nhập thật cần môi trường riêng.

`app/test/supabase_notification_repository_test.dart` dùng HTTP mock để kiểm tra bộ lọc/JWT, RPC payload, biên nhận lỗi, thiếu/hết hạn phiên, đổi tài khoản trong lúc chờ, refresh cùng tài khoản và ẩn lỗi nhạy cảm. HTTP mock không thay thế regression trên database.
