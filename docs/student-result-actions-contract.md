# Phần 2 — Khép kín luồng xử lý sửa chữa

## Phạm vi

Phần 2 dùng các chức năng Admin/KTV đã có và bổ sung backend, giao diện thật cho
DF-013/014/015: danh sách Chờ xác nhận, xác nhận đã khắc phục và yêu cầu sửa lại.
Không đánh dấu sửa/hủy/mở lại yêu cầu hoặc các chức năng quản trị khác là đã xong.

```text
Sinh viên tạo → pending
Admin phân công → assigned
KTV bắt đầu → in_progress
KTV gửi kết quả → awaiting_confirmation
  ├─ Sinh viên xác nhận → completed
  └─ Sinh viên yêu cầu sửa lại → awaiting_rework
       → KTV tiếp tục → in_progress → gửi kết quả mới → awaiting_confirmation
```

## Các file và hàm để review

1. `app/lib/app/dormfix_app.dart` khởi tạo repository Supabase của ba vai trò.
2. `app/lib/features/admin_requests/data/admin_request_repository.dart`:
   `assignRequest()` gọi `admin_assign_request`, server phân công và ghi lịch sử.
3. `app/lib/features/technician_jobs/data/technician_workflow_repository.dart`:
   `startJob()`, `submitResult()` và `continueJob()` gọi các RPC tương ứng;
   server kiểm tra phân công hiện tại và phiên bản công việc.
4. `app/lib/features/student_confirmation/presentation/awaiting_confirmation_screen.dart`
   lọc danh sách chính chủ qua `AdapterConfirmationRepository`; mở chi tiết thật.
5. `app/lib/features/student_requests/presentation/request_detail_screen.dart`:
   `_openResultAction()` mở biểu mẫu theo hành động, nhận biên nhận rồi tải lại
   chi tiết và danh sách. Hai nút chỉ xuất hiện ở Chờ xác nhận khi repository hỗ trợ.
6. `app/lib/features/student_confirmation/presentation/student_result_action_form.dart`:
   `_submit()` giữ một `StudentConfirmationSubmission` bất biến qua lần thử lại;
   lý do sửa lại bắt buộc, nhận xét xác nhận tùy chọn. Ảnh có xem trước và xóa trước gửi.
7. `app/lib/features/student_requests/data/supabase_request_repository.dart`:
   `submitConfirmation()` tải ảnh tạm rồi gọi RPC; kiểm tra đúng ID, phiên bản,
   trạng thái và feedback ID của biên nhận trước khi báo thành công.
8. `database/20261109173649_student_result_confirmation.sql`: hai RPC công khai
   gọi helper riêng `_student_resolve_result()`, xử lý toàn bộ thay đổi nghiệp vụ
   trong một giao dịch. Mã mẫu cũ ghi trực tiếp nhiều bảng đã được loại bỏ.

## Quy tắc server

| RPC | Tham số | Kết quả |
| --- | --- | --- |
| `student_confirm_result` | `p_request_id`, `p_expected_version`, `p_action_id`, `p_note` tùy chọn | `completed`, thời gian hoàn tất từ server |
| `student_request_rework` | `p_request_id`, `p_expected_version`, `p_action_id`, `p_reason`, `p_photos` | `awaiting_rework`, giữ nguyên KTV, phản hồi và ảnh riêng |

Biên nhận có `request_id`, `action_id`, `status`, `version`, `feedback_id`,
`replayed`. Feedback ID bằng action ID khi sửa lại, null khi xác nhận.

Mỗi lần gọi kiểm tra UID từ JWT, Sinh viên active/đã đổi mật khẩu, yêu cầu chính
chủ, trạng thái Chờ xác nhận và phiên bản khớp. Phân công hiện tại phải có kết quả
mới nhất do đúng KTV gửi. Kết quả hiện đại cần khớp phiên bản trước khi gửi; dữ
liệu cũ thiếu phiên bản chỉ được chấp nhận khi khớp đúng phân công hiện tại.
Sinh viên vẫn được xác nhận/sửa lại yêu cầu phòng cũ. Ràng buộc phòng hiện tại
chỉ áp dụng cho chức năng mở lại DF-016, chưa triển khai trong phần này.

Server khóa hồ sơ, action UUID và yêu cầu; lưu trạng thái, feedback/ảnh và lịch
sử cùng giao dịch. Trigger 013 tạo thông báo KTV đúng một lần khi đổi trạng thái.
Không cấp quyền ghi trực tiếp bảng nghiệp vụ cho ứng dụng. Các RPC chỉ cấp
EXECUTE cho authenticated và tự kiểm tra quyền; helper riêng không được gọi từ client.

## Ảnh và thử lại

Ảnh sửa lại nằm trong bucket private `repair-images` với đường dẫn:

```text
student-feedback/{uid}/{request_id}/{expected_version}/{action_id}/{photo_id}.{extension}
```

Tối đa 5 ảnh JPG/PNG/WebP, mỗi ảnh tối đa 5 MiB (5.242.880 byte). Upload không ghi
đè. Server kiểm tra đường dẫn, người sở hữu object, MIME, dung lượng và toàn bộ
danh sách ảnh tạm trước khi lưu. Ảnh đã gửi không được sửa/xóa bởi cleanup; ảnh
tạm lỗi được xóa theo chính sách có kiểm tra quyền. Đọc ảnh dùng JWT và kiểm tra
lại quyền yêu cầu; không tạo public URL.

Lịch sử lưu `student_action_fingerprint`, là SHA-256 của lần gửi gốc. Cùng UUID
và nội dung trả về biên nhận gốc mà không thêm feedback/lịch sử/thông báo, kể cả
sau vòng xử lý tiếp theo; UUID có nội dung khác bị từ chối. Biên nhận replay là
kết quả của hành động gốc; giao diện luôn tải lại trạng thái hiện tại từ server.

Nếu chưa rõ server đã lưu hay chưa, form khóa nội dung và giữ cùng UUID/ảnh để
người dùng bấm **Kiểm tra lại**. Repository thử finalize trước, không xóa ảnh khi
kết quả chưa rõ. UUID/bản nhập chỉ giữ trong RAM khi form còn sống. Sau khi đóng
form hoặc khởi động lại app phải đối chiếu chi tiết trước khi gửi hành động khác.
Thay đổi phiên đăng nhập làm dữ liệu đang chờ bị loại bỏ; khi trở lại từ nền,
biểu mẫu xác minh lại quyền trước khi cho thao tác.

## Demo thủ công

1. Sinh viên tạo một yêu cầu và ghi lại mã DF.
2. Đăng nhập Admin → Yêu cầu → mở đúng mã → phân công KTV.
3. Đăng nhập KTV → Công việc → mở đúng mã → Bắt đầu xử lý → gửi kết quả/ảnh.
4. Sinh viên → Chờ xác nhận → mở đúng mã, xem kết quả và ảnh.
5. Chọn Yêu cầu sửa lại, nhập lý do và ảnh tùy chọn; trạng thái thành Chờ xử lý lại.
6. KTV mở công việc → Tiếp tục xử lý → gửi kết quả mới.
7. Sinh viên xem cả hai vòng, chọn Xác nhận đã khắc phục; trạng thái thành Hoàn tất.
8. Admin và KTV mở lại cùng mã để đối chiếu lịch sử, phản hồi và thông báo.

## Kiểm tra tích hợp SDK theo yêu cầu

`app/tool/phase2_live_smoke_test.dart` là kiểm tra thủ công, không nằm trong
thư mục `test/` nên không được CI chạy tự động. Lệnh dưới đây tạo **một yêu cầu
demo mới** trên đúng project DormFix, chạy hai vòng qua repository thật, giữ dữ
liệu để demo, rồi đăng xuất các phiên kiểm thử. Ba tài khoản demo cần dùng chung
mật khẩu do người chạy cung cấp; không lưu mật khẩu vào mã nguồn.

Chạy từ thư mục `app`, sau khi đã cấu hình `config/local.json`:

```sh
DORMFIX_RUN_LIVE_DEMO=1 DORMFIX_DEMO_PASSWORD='<mật-khẩu-demo>' \
  flutter test --no-pub tool/phase2_live_smoke_test.dart
```

Kết quả nghiệm thu và giới hạn kiểm thử được ghi tại `database/DEPLOYMENT.md`.

Mốc nghiệm thu 10/11/2026: `DF000297` đã Hoàn tất sau hai vòng bằng SDK thật;
`DF000287` được chuẩn bị ở Chờ xác nhận để thao tác demo. Trạng thái có thể đổi
sau khi người dùng tiếp tục xử lý; luôn đối chiếu dữ liệu đang hiển thị.
