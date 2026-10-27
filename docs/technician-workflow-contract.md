# Hợp đồng nghiệp vụ Kỹ thuật viên — DF-023–DF-026

Migration `database/005_technician_workflow.sql` triển khai DF-023/DF-026, áp dụng một lần sau `001_schema.sql`, `003_get_my_profile.sql`, `004_technician_jobs.sql`. Migration bổ sung `database/007_technician_continue_rework.sql` triển khai DF-024 sau các migration trước đó, gồm `005` và `006`; không sửa migration đã triển khai.

Migration `database/008_technician_confirm_transfer.sql` bổ sung DF-025 sau `007`: KTV mới xác nhận tiếp tục công việc được Admin chuyển khi đang `in_progress`. Phạm vi gồm bắt đầu công việc được giao, tiếp tục sau yêu cầu sửa lại, xác nhận tiếp tục sau chuyển giao và gửi kết quả sửa chữa. Backend Admin tạo giao dịch chuyển người vẫn là phần việc riêng, chưa được nối trong ứng dụng hiện tại.

## Quyền thao tác

Mỗi RPC kiểm tra JWT và hồ sơ trên database: tài khoản phải có role `technician`, trạng thái `active`, đã đổi mật khẩu tạm; yêu cầu phải đang giao cho đúng tài khoản đó. Client không được ghi trực tiếp vào các bảng nghiệp vụ.

Các thao tác khóa hồ sơ, yêu cầu và lần phân công hiện tại, sau đó kiểm tra lại trạng thái và `version`. Chuyển công việc hoặc đổi trạng thái trong lúc người dùng mở màn hình sẽ khiến thao tác cũ bị từ chối. Khi có xung đột, tải lại chi tiết trước khi thao tác tiếp.

`request_assignments.started_at` là bằng chứng làm việc do server ghi. Dữ liệu cũ để `NULL`; không suy ra quyền gửi kết quả chỉ từ trạng thái `in_progress`. Quyền gửi cần `needs_transfer_confirmation = false` và ít nhất một bằng chứng hợp lệ: `started_at >= assigned_at` hoặc `transfer_confirmed_at >= assigned_at`. DF-024 giữ nguyên `started_at` đã có; nếu lần phân công hiện tại chưa có bằng chứng bắt đầu, thao tác tiếp tục tạo mốc này bằng thời gian server. Cờ đang chờ xác nhận chuyển luôn chặn DF-024; thao tác tiếp tục không tự xác nhận chuyển thay DF-025.

## Quyền hiển thị trong chi tiết công việc

RPC `technician_get_job(p_request_id)` giữ nguyên dữ liệu cũ, thêm trường gốc:

```json
{
  "workflow": {
    "can_start": true,
    "can_continue": false,
    "can_confirm_transfer": false,
    "can_submit_result": false,
    "blocked_reason": null
  }
}
```

| Tình huống | can_start | can_continue | can_confirm_transfer | can_submit_result | blocked_reason |
| --- | --- | --- | --- | --- | --- |
| `assigned`, có lần phân công hiện tại | true | false | false | false | null |
| `in_progress`, có bằng chứng bắt đầu hoặc xác nhận chuyển, không chờ xác nhận chuyển | false | false | false | true | null |
| Thiếu lần phân công hiện tại | false | false | false | false | `ASSIGNMENT_NOT_READY` |
| `in_progress`, cần xác nhận chuyển | false | false | true | false | `TRANSFER_CONFIRMATION_REQUIRED` |
| `awaiting_rework`, có cờ cần xác nhận chuyển chưa hợp lệ với hợp đồng Admin | false | false | false | false | `TRANSFER_CONFIRMATION_REQUIRED` |
| `in_progress`, thiếu bằng chứng bắt đầu | false | false | false | false | `START_REQUIRED` |
| `awaiting_rework`, có lần phân công hiện tại, không chờ xác nhận chuyển | false | true | false | false | `CONTINUE_REQUIRED` |
| Trạng thái còn lại | false | false | false | false | `READ_ONLY` |

`can_continue` và `can_confirm_transfer` là các trường bổ sung trong mọi nhánh. Migration 008 giữ nguyên các trường quyền và lý do chặn của 007; chỉ thêm cờ xác nhận chuyển. Nếu server cũ chưa có `workflow`, client mặc định mọi quyền là `false`; nếu thiếu riêng một trường bổ sung, cờ đó mặc định là `false`. Các trường hiện diện phải có đúng kiểu; tối đa một quyền ghi được bật. Các cờ hỗ trợ giao diện; RPC vẫn tự kiểm tra quyền. `CONTINUE_REQUIRED` và `TRANSFER_CONFIRMATION_REQUIRED` cho biết cần thực hiện thao tác tương ứng trước khi gửi kết quả, nên có thể đi cùng quyền thực hiện chính thao tác đó.

## DF-023: bắt đầu công việc

```text
technician_start_job(p_request_id uuid, p_expected_version integer)
```

Chỉ chấp nhận `assigned` cùng `version` mới nhất. Trong một transaction, server ghi `started_at`, đổi yêu cầu sang `in_progress`, tăng `version` và thêm một lịch sử `started`.

```json
{"request_id":"uuid","status":"in_progress","version":2}
```

Gọi lại với phiên bản cũ sẽ báo xung đột, không tạo thêm lịch sử. Client tải lại chi tiết để xác định kết quả sau lỗi mạng.

## DF-024: tiếp tục sau yêu cầu sửa lại

```text
technician_continue_job(p_request_id uuid, p_expected_version integer)
```

Chỉ KTV đang được giao yêu cầu, có tài khoản `active` và đã đổi mật khẩu tạm, được tiếp tục khi trạng thái là `awaiting_rework` và `version` còn khớp. Lần phân công hiện tại phải thuộc đúng KTV, chưa kết thúc và không có `needs_transfer_confirmation = true`. Thiếu bằng chứng bắt đầu ở lần phân công mới hoặc dữ liệu cũ không chặn tiếp tục; server tạo bằng chứng qua `started_at = coalesce(started_at, thời_gian_server)`.

RPC dùng lại khóa chia sẻ hồ sơ từ `_technician_workflow_actor()`, rồi khóa cập nhật yêu cầu và lần phân công hiện tại. Trong cùng transaction, server giữ mốc bắt đầu cũ nếu có, chuyển yêu cầu sang `in_progress`, tăng `version` đúng một lần, cập nhật `updated_at` và ghi đúng một lịch sử `continued`: người thao tác là KTV hiện tại, trạng thái cũ `awaiting_rework`, trạng thái mới `in_progress`, thời gian trùng `updated_at`.

```json
{"request_id":"uuid","status":"in_progress","version":6}
```

Biên nhận chỉ có ba trường trên, không có `result_id` hoặc cơ chế replay. Gọi lặp với phiên bản cũ hoặc gọi lại khi đã `in_progress` trả `JOB_STATE_CONFLICT`; sau lỗi mạng, client tải lại chi tiết để xác định trạng thái. Trước khi tiếp tục thành công, gửi kết quả và tải ảnh cho vòng sửa mới vẫn bị chặn. Sau đó, luồng DF-026 hiện có dùng bằng chứng `started_at` và phiên bản mới để gửi một kết quả mới.

Thao tác tiếp tục giữ nguyên cờ/thời gian xác nhận chuyển, kết quả, lý do sửa lại, phản hồi và mọi ảnh cũ; không tạo thông báo vì schema chưa có sự kiện thông báo tiếp tục. RPC chỉ cấp quyền thực thi cho `authenticated`, vẫn tự kiểm tra role/trạng thái/mật khẩu; không cấp quyền ghi trực tiếp bảng hoặc thay đổi các hàm gửi kết quả/Storage.

## DF-025: xác nhận tiếp tục công việc được chuyển khi đang xử lý

```text
technician_confirm_transfer(p_request_id uuid, p_expected_version integer)
```

RPC chỉ nhận yêu cầu `in_progress`, phiên bản khớp và lần phân công hiện tại của đúng KTV có `needs_transfer_confirmation = true`. Tài khoản phải `active`, đã đổi mật khẩu tạm. Không áp dụng cho `assigned` (bắt đầu bằng DF-023), `awaiting_rework` (tiếp tục bằng DF-024) hoặc dùng để bổ sung bằng chứng cho dữ liệu `in_progress` cũ không có cờ chờ xác nhận. Lần phân công sai hoặc thiếu trả `ASSIGNMENT_NOT_READY`; trạng thái sai, phiên bản cũ, không có cờ chờ xác nhận hoặc `assigned_at` bị đặt trong tương lai trả `JOB_STATE_CONFLICT`.

Server dùng lại khóa chia sẻ hồ sơ từ `_technician_workflow_actor()`, rồi khóa cập nhật yêu cầu và lần phân công hiện tại. Trong cùng transaction, server đặt `needs_transfer_confirmation = false`, ghi `transfer_confirmed_at` bằng thời gian server, giữ nguyên `started_at` kể cả khi đang `NULL`, giữ trạng thái yêu cầu `in_progress`, tăng `version` đúng một lần và ghi `updated_at`. Một lịch sử `transfer_confirmed` lưu KTV hiện tại ở `actor_id`, trạng thái cũ/mới đều `in_progress`, và thời gian trùng `transfer_confirmed_at`/`updated_at`. Người xác nhận được gắn với KTV của chính lần phân công đó; lịch sử phân công giữ lại danh tính và thời gian khi có lần chuyển tiếp theo.

```json
{"request_id":"uuid","status":"in_progress","version":9}
```

Biên nhận có đúng ba trường, không có `result_id` hoặc replay. Gọi lại với phiên bản cũ, hoặc phiên bản mới khi cờ đã được xóa, trả `JOB_STATE_CONFLICT`; client tải lại chi tiết khi không rõ kết quả sau lỗi mạng. Thao tác không đổi kết quả, phản hồi, ảnh hoặc các lần phân công khác; không tạo thông báo vì schema không có sự kiện xác nhận tiếp tục. Hàm là `security definer` với `search_path` rỗng, chỉ `authenticated` được gọi; helper quyền vẫn riêng tư, không có quyền ghi trực tiếp bảng mới.

Trước xác nhận, luồng gửi kết quả và tải ảnh bị chặn ngay cả khi còn `started_at` hoặc có xác nhận ở lần phân công cũ. Sau xác nhận, các hàm DF-026/Storage hiện có dùng `transfer_confirmed_at >= assigned_at` của lần phân công hiện tại và phiên bản mới để cho gửi; không cần sửa các hàm này hoặc tạo cột mới. Xác nhận không tạo thời điểm bắt đầu giả và không dùng lại bằng chứng của người cũ.

### Hợp đồng bắt buộc với backend Admin chuyển người

Backend Admin chuyển người chưa được triển khai trong các migration hiện tại; màn Admin hiện là giao diện chưa nối dữ liệu. DF-025 chỉ xử lý xác nhận trên lần phân công đã được tạo đúng. Một giao dịch Admin sau này phải:

1. Kiểm tra quyền Admin, KTV mới và `version`; khóa yêu cầu/lần phân công hiện tại theo cùng thứ tự với các thao tác KTV.
2. Kết thúc lần phân công cũ bằng `ended_at` và `end_reason = 'transferred'`, giữ nguyên bằng chứng và lịch sử của hàng cũ.
3. **Thêm hàng phân công mới** với KTV mới, Admin thực hiện, `assigned_at` từ server, lý do chuyển và các snapshot. `started_at`/`transfer_confirmed_at` phải `NULL`; `needs_transfer_confirmation` chỉ là `true` khi yêu cầu đang `in_progress`, là `false` cho `assigned`/`awaiting_rework`.
4. Đổi `assigned_technician_id`, giữ nguyên trạng thái `assigned`/`in_progress`/`awaiting_rework`, tăng `version`, cập nhật `updated_at` và ghi lịch sử/thông báo chuyển giao cùng transaction. Không tái sử dụng hàng phân công cũ hoặc chỉ đổi ID KTV trên hàng đó.

Mỗi lần chuyển tạo quyền xác nhận mới. Với A → B → A, lần phân công thứ ba của A vẫn có bằng chứng `NULL` và cờ chờ xác nhận; xác nhận của A ở lần đầu hoặc của B ở lần hai không áp dụng. Phiên bản của yêu cầu phải tăng khi chuyển để màn hình cũ, kể cả cùng UID A, không thể xác nhận nhầm lần mới. Nếu gặp `awaiting_rework` có cờ chờ xác nhận, đây là dữ liệu không đúng hợp đồng Admin; DF-025 không tự chuyển trạng thái hay xóa cờ để chữa dữ liệu.

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
| `22023` | `JOB_VERSION_REQUIRED` | Thiếu phiên bản nguyên dương hợp lệ; luồng gửi kết quả còn yêu cầu ID kết quả |
| `22023` | `RESULT_CONTENT_REQUIRED` | Nhập nội dung kết quả |
| `22023` | `INVALID_RESULT_PHOTOS` | Kiểm tra ảnh, đường dẫn, quyền sở hữu, MIME và dung lượng |
| `22023` | `RESULT_REPLAY_MISMATCH` | Không sửa payload của một lần gửi đã chốt |

Lỗi upload hoặc remove riêng đến từ Storage API. Nếu kết quả chưa rõ sau lỗi mạng, không báo gửi thất bại chắc chắn và không tạo ID mới ngay; thử lại cùng lần gửi hoặc tải lại dữ liệu trước.

## Kiểm chứng

`database/tests/005_technician_workflow.sql` chạy với quyền SQL Editor/database owner, tạo tài khoản Auth giả không mật khẩu, giả lập role/JWT và `ROLLBACK` toàn bộ fixture. Kiểm tra quyền, tài khoản bị khóa/thu hồi/chưa đổi mật khẩu, phiên bản, lần phân công, bằng chứng bắt đầu/chuyển, staging 5/6 ảnh, đường dẫn giả, metadata sở hữu/MIME/dung lượng, nội dung bắt buộc, tính nguyên tử, thử lại và giữ lịch sử kết quả.

`database/tests/007_technician_continue_rework.sql` chạy sau migration 007 theo cùng quy tắc fixture và rollback. Kiểm tra từ chối anonymous, thiếu đăng nhập, sai role, thiếu hồ sơ, tài khoản khóa/thu hồi/chưa đổi mật khẩu; yêu cầu lạ/đã chuyển, thiếu hoặc sai lần phân công hiện tại, trạng thái sai, phiên bản thiếu/không hợp lệ/cũ và gọi lặp; chặn xác nhận chuyển; giữ mốc bắt đầu cũ, tạo mốc cho dữ liệu cũ/lần phân công mới; đúng một lịch sử mỗi lần tiếp tục, không có thông báo tiếp tục; không ghi trực tiếp bảng. Hai vòng tiếp tục rồi gửi bằng DF-026 kiểm tra kết quả mới được thêm và giữ nguyên kết quả, phản hồi, metadata ảnh cũ. Regression 005 bỏ riêng các khóa bổ sung `can_continue`/`can_confirm_transfer` khi so sánh nguyên đối tượng quyền cũ; regression 007 bỏ riêng `can_confirm_transfer`.

`database/tests/008_technician_confirm_transfer.sql` chạy sau 008 với cùng quy tắc passwordless Auth, Storage metadata và rollback. Kiểm tra ACL/JWT/role/trạng thái/mật khẩu; yêu cầu lạ, người cũ, thiếu/sai lần phân công, trạng thái sai, phiên bản thiếu/không hợp lệ/cũ, không có cờ chờ, thời gian phân công tương lai và gọi lặp. Kiểm tra giữ nguyên `started_at` cũ/`NULL`, thời gian xác nhận/lịch sử/`updated_at` đồng nhất, mỗi lần một lịch sử và không thông báo xác nhận. Fixture do database owner mô phỏng hai lần chuyển A → B → A bằng hàng mới và phiên bản mới, chứng minh UID/phiên bản/bằng chứng cũ không vượt được cờ chờ, sau đó dùng nguyên DF-026/Storage để tải metadata và gửi kết quả mới mà giữ dữ liệu cũ. Đây không phải kiểm thử backend Admin chuyển người.

Fixture Storage chỉ là metadata, không có byte ảnh thật. Do `protect_delete()`, kiểm tra SQL xác nhận điều kiện helper và policy DELETE thay vì xóa trực tiếp; việc upload/download/remove file thật qua Storage API và tranh chấp hai session song song cần kiểm chứng riêng. Không suy ra các kiểm tra đó đã chạy chỉ từ dòng PASS của SQL regression.
