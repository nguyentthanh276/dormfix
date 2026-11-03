# Theo dõi công việc Kỹ thuật viên — DF-027

Migration `database/013_technician_tracking.sql` áp dụng một lần sau `012_admin_request_resolution.sql`. File chỉ thêm ba RPC và một trigger; không sửa migration đã triển khai, không đổi tài khoản hoặc backfill thông báo cũ. Đã áp dụng lên project DormFix ngày 03/11/2026 sau khi migration cùng regression đạt PASS trong transaction rollback; xem `database/DEPLOYMENT.md`. Không chạy lại migration đã áp dụng.

## Danh tính và quyền

Cả ba RPC lấy người dùng từ `auth.uid()`, không nhận technician ID hoặc role từ ứng dụng. Chỉ `authenticated` có quyền gọi. Hồ sơ hiện tại phải là Kỹ thuật viên `active`, đã đổi mật khẩu tạm. `technician_mark_notification_read` dùng helper `_technician_workflow_actor()` để khóa chia sẻ hồ sơ trong transaction; khóa/thu hồi tài khoản và ghi trạng thái đã đọc được tuần tự hóa.

Các function dùng `search_path` rỗng, schema-qualified SQL và thu hồi quyền mặc định. Không thêm quyền ghi bảng cho client. RLS và quyền đọc chi tiết/Storage hiện có vẫn kiểm tra người đang được giao công việc.

| SQLSTATE | Message | Xử lý |
| --- | --- | --- |
| `28000` | `AUTH_REQUIRED` | Đăng nhập lại. |
| `42501` | `TECHNICIAN_ACCESS_DENIED` | Xóa dữ liệu đang hiển thị; kiểm tra lại hồ sơ/phiên. |
| `P0002` | `NOTIFICATION_NOT_FOUND` | Không tìm thấy thông báo của chính người nhận; tải lại danh sách. ID lạ và thông báo người khác cùng trả lỗi này. |

## Lịch sử từng lần phân công

`technician_list_work_history()` trả JSONB array, `[]` nếu chưa có phân công; sắp xếp `assigned_at DESC, assignment_id DESC`. Mỗi lần phân công là một dòng, kể cả A → B → A. Chỉ trả các lần phân công có `technician_id = auth.uid()`.

```json
{
  "assignment_id": "uuid",
  "request_id": null,
  "request_code": "DF000001",
  "title": "Tiêu đề lúc được giao",
  "room_code": "A101",
  "assigned_at": "2026-10-20T01:00:00+00:00",
  "ended_at": "2026-10-21T01:00:00+00:00",
  "status": null,
  "can_open_detail": false
}
```

`can_open_detail` chỉ là `true` khi lần phân công chưa kết thúc **và** yêu cầu vẫn có `assigned_technician_id` trùng người gọi. Khi đó `request_id` và trạng thái hiện tại được trả để mở chi tiết bằng `technician_get_job`; công việc Hoàn tất/Đã hủy vẫn xem đầy đủ và chỉ đọc theo hợp đồng DF-022/DF-026.

Mọi lần phân công cũ chỉ đọc `request_code_snapshot`, `title_snapshot`, `room_code_snapshot` cùng `assigned_at`/`ended_at` của chính lần đó. `request_id` và `status` là JSON null. Không trả mô tả, người liên hệ, kết quả, ảnh hoặc cập nhật sau chuyển giao. Việc yêu cầu được giao lại cho cùng Kỹ thuật viên không làm dòng phân công cũ có thêm quyền; chỉ dòng phân công mới hiện tại mở được chi tiết. Backend vẫn kiểm tra lại quyền khi mở chi tiết hoặc tải ảnh, nên dữ liệu danh sách cũ không cấp quyền truy cập.

## Danh sách và trạng thái thông báo

`technician_list_notifications()` trả array thông báo có `recipient_id = auth.uid()`, mới nhất trước theo `created_at DESC, id DESC`. Mỗi dòng có đúng các trường:

```json
{
  "id": "uuid",
  "event_type": "transferred_out",
  "message": "Công việc của bạn đã được chuyển cho Kỹ thuật viên khác.",
  "created_at": "2026-10-21T01:00:00+00:00",
  "read_at": null,
  "request_id": null,
  "can_open_detail": false
}
```

`request_id` chỉ được trả khi yêu cầu hiện vẫn giao cho người gọi. Bấm thông báo đánh dấu đã đọc; ứng dụng chỉ mở chi tiết khi `can_open_detail=true`. Nếu quyền thay đổi sau lúc đọc danh sách, `technician_get_job` tiếp tục từ chối yêu cầu và xóa dữ liệu chi tiết theo luồng hiện có.

`technician_mark_notification_read(p_notification_id uuid)` chỉ cập nhật thông báo của người gọi. Server đặt `read_at` bằng thời gian server nếu chưa đọc, giữ nguyên mốc đó khi gọi lặp và trả `{"id":"uuid","read_at":"timestamptz"}`. Client không được chọn người nhận, thời gian đọc hoặc sửa nội dung.

## Tạo thông báo cùng transaction nguồn

Trigger `technician_tracking_events` chạy sau UPDATE `repair_requests.status` hoặc `assigned_technician_id`. Chỉ có chuyển đổi giá trị thực sự mới tạo sự kiện; rollback thao tác nguồn cũng rollback thông báo.

| Thay đổi | Người nhận / event_type |
| --- | --- |
| Chưa có người → được giao KTV | KTV mới / `assigned` |
| KTV A → KTV B | A / `transferred_out`; B / `transferred_in` |
| Chuyển sang Đã hủy | KTV đang được giao, hoặc người cũ nếu cùng thao tác bỏ phân công / `cancelled` |
| Chuyển sang Chờ xử lý lại | KTV được giao / `rework_requested` |
| Chuyển sang Hoàn tất | KTV được giao / `completed`, bao gồm Admin xác nhận thay Sinh viên đã thu hồi |

Bỏ phân công về null không tạo thông báo chuyển giao riêng, vì một lần hủy không được tạo đồng thời thông báo hủy và chuyển người. Dữ liệu phân công cũ vẫn có trong lịch sử. Trigger chỉ gửi tới profile role Kỹ thuật viên; nội dung là thông báo sự kiện chung, không sao chép tiêu đề, dữ liệu cá nhân, lý do hoặc kết quả/ảnh. Các sự kiện chỉ được tạo từ thay đổi database sau khi migration áp dụng; thao tác mock cục bộ và dữ liệu cũ không tự sinh thông báo. Không có thông báo đẩy hoặc đăng ký Realtime.

## Kiểm chứng

`database/tests/013_technician_tracking.sql` tạo Auth user tổng hợp không có mật khẩu/phiên và giả lập role/JWT. Script kết thúc bằng ROLLBACK, kiểm tra role/tài khoản/ACL, chỉ đọc dữ liệu chính chủ, snapshot sau chuyển giao, A → B → A, current completed/cancelled chỉ đọc, trigger trong transaction, không tạo lặp khi no-op, đánh dấu đọc idempotent và từ chối sửa thông báo người khác/ghi bảng trực tiếp. Các truy vấn chỉ thay fixture có UUID ngẫu nhiên; không đổi tài khoản hoặc yêu cầu demo hiện có.

Các test 007/008 được giới hạn phép đếm vào sự kiện `repair_reported` mà chúng sở hữu; sự kiện chuyển giao do DF-027 tạo không bị tính là thông báo từ thao tác xác nhận tiếp tục. SQL role/JWT mô phỏng không thay thế đăng nhập thật và kiểm thử luồng Flutter/HTTP. Kiểm thử giao dịch song song hai session cần môi trường riêng.
