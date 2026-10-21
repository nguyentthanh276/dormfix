# Hợp đồng nghiệp vụ Kỹ thuật viên — DF-023, DF-026

Migration: `database/005_technician_workflow.sql`, áp dụng một lần sau `001_schema.sql`, `003_get_my_profile.sql`, `004_technician_jobs.sql`.

Phạm vi gồm bắt đầu công việc được giao và gửi kết quả sửa chữa. Tiếp tục sau yêu cầu sửa lại (DF-024) và xác nhận tiếp nhận việc được chuyển (DF-025) chưa được triển khai trong migration này.

## Quyền thao tác

Mỗi RPC kiểm tra JWT và hồ sơ trên database: tài khoản phải có role `technician`, trạng thái `active`, đã đổi mật khẩu tạm; yêu cầu phải đang giao cho đúng tài khoản đó. Client không được ghi trực tiếp vào các bảng nghiệp vụ.

Các thao tác khóa hồ sơ, yêu cầu và lần phân công hiện tại, sau đó kiểm tra lại trạng thái và `version`. Chuyển công việc hoặc đổi trạng thái trong lúc người dùng mở màn hình sẽ khiến thao tác cũ bị từ chối. Khi có xung đột, tải lại chi tiết trước khi thao tác tiếp.

`request_assignments.started_at` là bằng chứng bắt đầu do server ghi. Dữ liệu cũ để `NULL`; không suy ra quyền gửi kết quả chỉ từ trạng thái `in_progress`. Công việc được chuyển khi đang xử lý phải có `needs_transfer_confirmation = false` và bằng chứng `transfer_confirmed_at >= assigned_at` từ luồng DF-025 sau này. `awaiting_rework` cần luồng DF-024 trước khi tiếp tục.

## Quyền hiển thị trong chi tiết công việc

RPC `technician_get_job(p_request_id)` giữ nguyên dữ liệu cũ, thêm trường gốc:

```json
{
  "workflow": {
    "can_start": true,
    "can_submit_result": false,
    "blocked_reason": null
  }
}
```

| Tình huống | can_start | can_submit_result | blocked_reason |
| --- | --- | --- | --- |
| `assigned`, có lần phân công hiện tại | true | false | null |
| `in_progress`, có bằng chứng bắt đầu hoặc xác nhận chuyển | false | true | null |
| Thiếu lần phân công hiện tại | false | false | `ASSIGNMENT_NOT_READY` |
| `in_progress`, cần xác nhận chuyển | false | false | `TRANSFER_CONFIRMATION_REQUIRED` |
| `in_progress`, thiếu bằng chứng bắt đầu | false | false | `START_REQUIRED` |
| `awaiting_rework` | false | false | `CONTINUE_REQUIRED` |
| Trạng thái còn lại | false | false | `READ_ONLY` |

Nếu server cũ chưa có `workflow`, client mặc định cả hai quyền là `false`. Các cờ hỗ trợ giao diện; RPC vẫn tự kiểm tra quyền.

## DF-023: bắt đầu công việc

```text
technician_start_job(p_request_id uuid, p_expected_version integer)
```

Chỉ chấp nhận `assigned` cùng `version` mới nhất. Trong một transaction, server ghi `started_at`, đổi yêu cầu sang `in_progress`, tăng `version` và thêm một lịch sử `started`.

```json
{"request_id":"uuid","status":"in_progress","version":2}
```

Gọi lại với phiên bản cũ sẽ báo xung đột, không tạo thêm lịch sử. Client tải lại chi tiết để xác định kết quả sau lỗi mạng.

## DF-026: gửi kết quả sửa chữa

```text
technician_submit_result(
  p_request_id uuid,
  p_expected_version integer,
  p_result_id uuid,
  p_content text,
  p_photos jsonb default []
)
```

Nội dung bắt buộc, loại bỏ khoảng trắng đầu/cuối, kể cả tab và xuống dòng. Ảnh tùy chọn: tối đa 5 ảnh, mỗi ảnh từ 1 byte đến 5 MiB (5.242.880 byte), JPEG, PNG hoặc WebP. Mỗi phần tử manifest có đúng bốn trường:

```json
{
  "id": "photo-uuid",
  "storage_path": "technician-results/user-uuid/request-uuid/2/result-uuid/photo-uuid.png",
  "mime_type": "image/png",
  "size_bytes": 128
}
```

Đường dẫn dùng UUID chữ thường dạng chuẩn; phiên bản là số nguyên dương không có số 0 đầu; đuôi hợp lệ là `.jpg`, `.jpeg`, `.png`, `.webp`. `p_result_id` là UUID tạo một lần cho lần gửi. Không trùng ID ảnh hoặc đường dẫn. Đường dẫn phải khớp tài khoản JWT, yêu cầu, phiên bản, kết quả và ID ảnh.

Server đối chiếu manifest với đối tượng đã có trong bucket riêng tư `repair-images`: `owner_id`, `metadata.mimetype` và `metadata.size` thực tế phải khớp. Chỉ gửi metadata hoặc đường dẫn chưa tải lên không đủ. Server không nhận đường dẫn tùy ý hoặc ảnh của tài khoản khác.

Khi hợp lệ, một transaction ghi kết quả, metadata ảnh, lịch sử `repair_reported`, thông báo cho sinh viên; đồng thời chuyển `in_progress` thành `awaiting_confirmation` và tăng `version`.

```json
{
  "request_id":"uuid",
  "result_id":"uuid",
  "status":"awaiting_confirmation",
  "version":3,
  "replayed":false
}
```

`repair_results.request_version` lưu phiên bản trước khi gửi. Kết quả cũ giữ nguyên; lần sửa tiếp theo thêm một kết quả mới thay vì sửa kết quả trước.

## Tải ảnh, thử lại và dọn ảnh tạm

1. Tạo `result_id`, ID từng ảnh và manifest; giữ nguyên các giá trị trong lần gửi đó.
2. Dùng Supabase Storage API tải ảnh lên `repair-images` tại đường dẫn đã định, `upsert: false`, đúng MIME. Bucket giữ chế độ private, giới hạn 5 MiB và JPEG/PNG/WebP.
3. Gọi RPC gửi kết quả với manifest. Trường hợp không có ảnh, truyền `[]`.
4. Nếu mất phản hồi sau khi đã gọi RPC, gọi lại RPC với **cùng** ID, phiên bản, nội dung và manifest trước khi tải lại ảnh. Payload giống nhau trả biên nhận `replayed: true`, không lặp kết quả, ảnh, lịch sử hoặc thông báo. Payload khác cùng ID báo `RESULT_REPLAY_MISMATCH`.
5. Sau khi gửi thành công, tải lại chi tiết. Nếu hủy hoặc lỗi chắc chắn chưa gửi, dọn ảnh tạm bằng Storage API. File đã được gắn vào kết quả không thể xóa bằng quyền client.

Storage chỉ cấp `INSERT` cho đường dẫn hợp lệ của KTV hiện tại, khi công việc đủ điều kiện gửi kết quả và chưa có kết quả mang ID đó; tối đa 5 đối tượng mỗi lần gửi. Quyền đọc ảnh tạm dành cho chủ sở hữu, chỉ khi chưa gắn vào `request_attachments`. Quyền `DELETE` chỉ áp dụng cho ảnh tạm của chính tài khoản; không có quyền `UPDATE`, nên không ghi đè, đổi tên hay di chuyển ảnh đã chốt. Việc đọc ảnh đã chốt tiếp tục dùng quyền đọc yêu cầu từ migration 004, do đó KTV cũ mất quyền xem sau khi chuyển công việc.

Các hàm staging, gửi kết quả và kiểm tra xóa cùng dùng advisory transaction lock theo `result_id`. Hàm kiểm tra xóa là `volatile`, kiểm tra lại attachment sau khi lấy khóa; gửi kết quả cũng khóa metadata Storage trước khi ghi. Ảnh tạm còn lại sau crash không thuộc kết quả; không có tác vụ tự động dọn ảnh trong phạm vi này.

Không ghi/xóa/sửa `storage.objects` trực tiếp trong mã ứng dụng hoặc migration. Supabase Storage mới còn chặn SQL DELETE bằng `storage.protect_delete()`. Luôn dùng Storage API cho file thật. Tài liệu chính thức: [quyền truy cập Storage](https://supabase.com/docs/guides/storage/security/access-control), [quyền sở hữu qua owner_id](https://supabase.com/docs/guides/storage/security/ownership), [metadata Storage](https://supabase.com/docs/guides/storage/schema/design).

## Mã lỗi

| SQLSTATE | message | Cách xử lý |
| --- | --- | --- |
| `28000` | `AUTH_REQUIRED` | Đăng nhập lại |
| `42501` | `TECHNICIAN_ACCESS_DENIED` | Kiểm tra role, trạng thái hoặc yêu cầu đổi mật khẩu |
| `P0002` | `JOB_NOT_FOUND` | Tải lại danh sách; công việc có thể đã chuyển |
| `P0001` | `JOB_STATE_CONFLICT` | Tải lại trạng thái và phiên bản |
| `P0001` | `ASSIGNMENT_NOT_READY` | Chưa có lần phân công hiện tại hợp lệ |
| `P0001` | `START_REQUIRED` | Thiếu bằng chứng bắt đầu; dữ liệu cũ cần xử lý theo nghiệp vụ |
| `P0001` | `TRANSFER_CONFIRMATION_REQUIRED` | Cần luồng xác nhận tiếp nhận DF-025 |
| `22023` | `JOB_VERSION_REQUIRED` | Thiếu ID kết quả hoặc phiên bản hợp lệ |
| `22023` | `RESULT_CONTENT_REQUIRED` | Nhập nội dung kết quả |
| `22023` | `INVALID_RESULT_PHOTOS` | Kiểm tra ảnh, đường dẫn, quyền sở hữu, MIME và dung lượng |
| `22023` | `RESULT_REPLAY_MISMATCH` | Không sửa payload của một lần gửi đã chốt |

Lỗi upload hoặc remove riêng đến từ Storage API. Nếu kết quả chưa rõ sau lỗi mạng, không báo gửi thất bại chắc chắn và không tạo ID mới ngay; thử lại cùng lần gửi hoặc tải lại dữ liệu trước.

## Kiểm chứng

`database/tests/005_technician_workflow.sql` chạy với quyền SQL Editor/database owner, tạo tài khoản Auth giả không mật khẩu, giả lập role/JWT và `ROLLBACK` toàn bộ fixture. Kiểm tra quyền, tài khoản bị khóa/thu hồi/chưa đổi mật khẩu, phiên bản, lần phân công, bằng chứng bắt đầu/chuyển, staging 5/6 ảnh, đường dẫn giả, metadata sở hữu/MIME/dung lượng, nội dung bắt buộc, tính nguyên tử, thử lại và giữ lịch sử kết quả.

Fixture Storage chỉ là metadata, không có byte ảnh thật. Do `protect_delete()`, kiểm tra SQL xác nhận điều kiện helper và policy DELETE thay vì xóa trực tiếp; việc upload/download/remove file thật qua Storage API và tranh chấp hai session song song cần kiểm chứng riêng. Không suy ra các kiểm tra đó đã chạy chỉ từ dòng PASS của SQL regression.
