# Hợp đồng đọc công việc Kỹ thuật viên — DF-020 / DF-022

Migration `database/004_technician_jobs.sql` đã được triển khai trên project DormFix ngày **15/10/2026**. Trước triển khai, migration và toàn bộ test SQL được chạy cùng transaction, đạt PASS rồi rollback. Sau triển khai đã xác minh hai RPC tồn tại, một policy đọc ảnh và không còn Auth user tạm của bộ test. Xem [ghi nhận triển khai](../database/DEPLOYMENT.md). Không chạy lại migration đã áp dụng hoặc seed demo cũ.

## Áp dụng và quyền truy cập

1. Áp dụng `004_technician_jobs.sql` một lần sau `001_schema.sql` và `003_get_my_profile.sql` bằng quyền quản trị database. Migration chạy trong transaction, không sửa tài khoản hoặc dữ liệu yêu cầu hiện có.
2. Bucket `repair-images` được tạo private nếu chưa có, giới hạn 5 MiB (5,242,880 byte), MIME `image/jpeg`, `image/png`, `image/webp`. Nếu bucket đã có cấu hình khác, migration báo `REPAIR_IMAGES_BUCKET_CONFIG_MISMATCH` và rollback; người phụ trách phải kiểm tra trước khi quyết định thay đổi. Migration không âm thầm ghi đè cấu hình.
3. Chạy `database/tests/004_technician_jobs.sql` bằng SQL Editor/database owner. Test tạo Auth/profile/yêu cầu và metadata Storage tổng hợp trong transaction rồi rollback; không đặt mật khẩu, tạo phiên đăng nhập hay đổi tài khoản demo. Test mô phỏng JWT subject và database role, chưa thay thế kiểm thử HTTP/Flutter thực tế.
4. Kiểm tra các policy Storage có sẵn. Policy permissive được kết hợp bằng OR; không để policy khác cho phép đọc rộng bucket này. Migration chỉ thêm SELECT policy, không thêm quyền upload/update/delete hoặc quyền ghi nghiệp vụ.

Chỉ `authenticated` được gọi RPC. Mỗi lần gọi lấy danh tính từ `auth.uid()` và kiểm tra profile hiện tại là `technician`, `active`, `must_change_password=false`. Admin cũng bị từ chối ở hai RPC chuyên biệt này. Không nhận technician ID hoặc role từ Flutter.

| SQLSTATE | Message | Xử lý phía ứng dụng |
|---|---|---|
| `28000` | `AUTH_REQUIRED` | Yêu cầu đăng nhập lại. |
| `42501` | `TECHNICIAN_ACCESS_DENIED` | Dừng hiển thị nghiệp vụ, tải lại hồ sơ để xử lý role/status/cờ mật khẩu. |
| `P0002` | `JOB_NOT_FOUND` | Xóa chi tiết đang hiển thị và báo công việc không còn truy cập được; tải lại danh sách. |

Người chưa đăng nhập ở role `anon` bị từ chối EXECUTE ngay tại database. `AUTH_REQUIRED` áp dụng khi role `authenticated` gọi mà không có `auth.uid()`. Không phân biệt ID không tồn tại, chưa giao, đã chuyển giao hoặc `null` qua lỗi chi tiết.

## `technician_list_jobs()`

Không có tham số. Trả JSONB array; không có việc trả `[]`. Chỉ lấy bản ghi có `repair_requests.assigned_technician_id = auth.uid()`, sắp xếp `updated_at DESC, id DESC`. Không lọc theo phòng Sinh viên hiện tại, lịch sử đã từng được giao hoặc trạng thái. `awaiting_rework`, `completed`, `cancelled` còn được giao đều xuất hiện.

```dart
final rows = await supabase.rpc('technician_list_jobs');
```

Mỗi phần tử có đúng các trường:

```json
{
  "id": "uuid",
  "request_code": "DF000001",
  "title": "Đèn không sáng",
  "description": "Mô tả sự cố",
  "room_code": "A101",
  "building": "Tòa A",
  "category_name": "Điện",
  "status": "awaiting_rework",
  "created_at": "2026-10-15T01:00:00+00:00",
  "updated_at": "2026-10-15T02:00:00+00:00",
  "version": 1
}
```

`room_code`, `building`, `category_name` lấy từ snapshot của yêu cầu. Đổi phòng Sinh viên hoặc sửa tên danh mục không làm đổi các giá trị lịch sử này. Mã trạng thái theo enum `repair_status`; thời gian là chuỗi timestamptz có múi giờ.

## `technician_get_job(p_request_id uuid)`

```dart
final detail = await supabase.rpc(
  'technician_get_job',
  params: {'p_request_id': requestId},
);
```

Trả object có các trường sau. Tất cả dữ liệu con chỉ thuộc yêu cầu đã được kiểm tra quyền. Các array luôn có giá trị, trả `[]` khi không có dữ liệu; sắp xếp thời gian tăng dần, cùng thời gian dùng `id ASC`.

| Trường | Nội dung |
|---|---|
| `request` | Cùng object công việc trong danh sách ở trên. |
| `student` | `{full_name, phone}`; không trả email hoặc mã định danh. |
| `attachments` | `[{id, storage_path, mime_type, size_bytes, result_id, feedback_id}]`, theo `created_at ASC`. `result_id` và `feedback_id` là UUID string hoặc JSON null. Cả hai null: ảnh nội dung; `result_id`: ảnh kết quả; `feedback_id`: ảnh phản hồi. |
| `results` | `[{id, content, submitted_at, technician_name}]`, theo `submitted_at ASC`. Giữ các lần báo kết quả trước. |
| `feedback` | `[{id, kind, reason, created_at, author_name}]`, theo `created_at ASC`; `kind` là `rework` hoặc `reopen`. |
| `history` | `[{id, action, actor_name, old_status, new_status, note, occurred_at}]`, theo `occurred_at ASC`. Ba trường status/note có thể null. |
| `assignments` | `[{id, technician_name, assigned_by_name, assigned_at, ended_at, transfer_reason, end_reason}]`, theo `assigned_at ASC`. Ba trường kết thúc/lý do có thể null. Người hiện được giao được xem đầy đủ lịch sử phân công của yêu cầu. |

Tên người thực hiện lấy từ hồ sơ hiện tại; schema hiện chưa lưu snapshot tên của họ. Nội dung, kết quả, phản hồi và liên kết ảnh lấy từ các bản ghi lịch sử riêng. Công việc `completed`/`cancelled` chỉ đọc; hợp đồng này không cung cấp thao tác bắt đầu, tiếp tục, báo kết quả hoặc cập nhật trạng thái.

Quyền luôn dựa trên người đang được giao, không dựa trên việc có một bản ghi `request_assignments` cũ. Sau khi chuyển giao, người cũ không gọi được detail và không tải mới được ảnh của yêu cầu. Quyền tóm tắt lịch sử của người cũ trong `001_schema.sql` không được mở rộng bởi migration này. Khi refresh/detail/image nhận lỗi mất quyền, Flutter phải bỏ dữ liệu chi tiết và bytes ảnh của màn hiện tại.

## Đọc ảnh private bằng JWT hiện tại

`storage_path` là tên object trong bucket `repair-images`, không phải URL công khai. Dùng SDK download với phiên đăng nhập hiện tại:

```dart
final bytes = await supabase.storage
    .from('repair-images')
    .download(attachment.storagePath);
```

Policy SELECT yêu cầu object có metadata trong `request_attachments` và `can_read_request(request_id)` cho người gọi hiện tại. Policy này còn phục vụ Admin/chính chủ theo quyền sẵn có của helper, không cấp quyền đọc cho người từng được giao. Không dùng public URL hoặc signed URL: URL đã ký có thể còn dùng được sau chuyển giao đến khi hết hạn. Bytes đã tải về thiết bị không thể bị thu hồi từ server, vì vậy bỏ cache trên màn khi mất quyền hoặc đăng xuất.

Migration không upload ảnh, không tạo object demo giả và không triển khai giới hạn 5 ảnh mỗi nhóm khi ghi. Luồng upload và xử lý ảnh của các Sprint sau cần quyền ghi và kiểm tra server riêng. Test SQL chỉ kiểm tra quyền nhìn metadata `storage.objects`; cần tải một object thật qua SDK và kiểm tra lại sau chuyển giao để xác minh HTTP Storage.

## Dữ liệu demo thủ công và xác minh tích hợp

`database/tests/004_technician_jobs_seed.sql` là seed tùy chọn **có lưu dữ liệu**, không tự triển khai cùng migration hoặc test rollback. Người phụ trách chỉ chạy sau khi quyết định thêm mẫu vào database dùng chung. Seed dùng ba hồ sơ demo hiện có, một phòng đang hoạt động của SV001 và một danh mục active, tạo bốn việc assigned/awaiting_rework/completed/cancelled cùng kết quả/phản hồi/lịch sử phù hợp. Seed từ chối chạy lại khi thấy marker `[DF020 DEMO]`; không ghi đè dữ liệu và không tạo ảnh không tồn tại.

Seed không thay đổi `must_change_password`. KTV001 hiện có thể vẫn bị gate theo hợp đồng Auth; phải hoàn tất đổi mật khẩu an toàn trước khi dùng nghiệp vụ trong Flutter. Không tự bỏ cờ trong SQL để chạy demo. Có thể xem dữ liệu bằng test role mô phỏng trong transaction rollback, nhưng điều đó không xác minh đăng nhập thật.

Sau khi áp dụng, kiểm tra qua phiên đăng nhập thật: danh sách đúng người, `awaiting_rework` hiển thị, completed/cancelled chỉ đọc, chi tiết hiện đủ contact/snapshot/ảnh/các lần kết quả/phản hồi/lịch sử. Chuyển giao bằng backend đã được phép hoặc fixture test: người cũ mất detail và tải ảnh mới; người mới đọc được. Kiểm thử locked/revoked/password-gated profile với phiên cũ và thử lỗi mạng/retry mà không giữ thông tin chi tiết đã mất quyền.
