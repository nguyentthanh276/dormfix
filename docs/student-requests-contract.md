# Phần 1 — Yêu cầu Sinh viên thật (DF-007–010)

## Phạm vi

- DF-007: tạo yêu cầu Chờ tiếp nhận, phòng lấy từ hồ sơ; loại sự cố đang hoạt động;
  tiêu đề/mô tả bắt buộc; tối đa 5 ảnh JPG/PNG/WebP, mỗi ảnh tối đa 5 MiB (5.242.880 byte).
- DF-008: danh sách chỉ có yêu cầu của người đang đăng nhập, gồm phòng cũ.
- DF-009: lọc trạng thái trên danh sách chính chủ đã tải, giữ lựa chọn khi đổi tab.
- DF-010: chi tiết, KTV hiện tại và số điện thoại, ảnh private, mọi kết quả,
  phản hồi và lịch sử các vòng xử lý.

Màn hình dùng repository Supabase. Mock phục vụ kiểm thử hoặc cấu hình được tiêm từ ngoài.
Phần 2 bổ sung xác nhận và yêu cầu sửa lại. [Luồng Phần 2](student-result-actions-contract.md)

Phần 3 bổ sung sửa, hủy và mở lại theo quyền của từng yêu cầu. [Migration Phần 3](../database/20261109175550_student_request_lifecycle.sql)

## Luồng tạo và các file để review

1. `app/lib/main.dart` khởi tạo Supabase với cấu hình của máy.
2. `app/lib/app/dormfix_app.dart` tạo `SupabaseRequestRepository` và repository
   thông báo Supabase; `startup_page.dart` truyền xuống Home của Sinh viên.
3. `presentation/student_home_page.dart` truyền repository vào
   `presentation/student_shell_screen.dart`.
4. Nút Tạo yêu cầu mở `presentation/create_request_screen.dart`. `_submit()` giữ một UUID và
   bản nhập cố định cho từng lần gửi, khóa nút và đợi kết quả.
5. `data/supabase_request_repository.dart`: `createRequest()` chuẩn bị dữ liệu;
   `_stagePhoto()` upload ảnh bằng JWT vào `repair-images`, không ghi đè file.
6. RPC `student_create_request` lấy `auth.uid()`, kiểm tra tài khoản/phòng/loại,
   xác minh ảnh đã upload, lưu yêu cầu + metadata ảnh + lịch sử trong một giao dịch.
7. Sau khi nhận đúng kết quả server, form đóng và danh sách tải lại từ Supabase.

Các đường dẫn feature ở trên nằm trong
`app/lib/features/student_requests/`. Giao diện chỉ dùng interface
`RequestRepository`, không tự ghi bảng hay tự chọn người sở hữu/phòng.

## Luồng đọc và ảnh

- `presentation/my_requests_screen.dart`: `MyRequestsScreen._load()` →
  `fetchMyRequests()` → `student_list_requests()`.
- `RequestFilter.byStatus()` lọc các trạng thái trên danh sách đó.
- `presentation/request_detail_screen.dart`: `RequestDetailScreen._load()` → `fetchRequestDetail()` →
  `student_get_request(p_request_id)`.
- `presentation/widgets/request_photo.dart` → `fetchAttachment()` kiểm tra lại chi tiết/quyền
  và metadata, rồi tải bytes bằng JWT. Không tạo public URL hoặc signed URL.
- Chạm ảnh mở viewer trong vùng điều hướng của tài khoản. Đăng xuất, đổi danh
  tính, nhận lỗi mất quyền hoặc đưa app ra nền sẽ loại bỏ bytes/ảnh đã hiển thị;
  khi tiếp tục sẽ xác minh quyền và tải lại theo vòng đời của ảnh.

## Hợp đồng RPC và kiểm tra server

| RPC | Nội dung |
| --- | --- |
| `student_list_categories()` | Các loại đang sử dụng cho Sinh viên đủ điều kiện |
| `student_list_requests()` | Tất cả yêu cầu chính chủ, mới nhất trước |
| `student_get_request(uuid)` | Chính chủ, contact KTV, metadata ảnh, kết quả/phản hồi/lịch sử |
| `student_create_request(uuid,text,uuid,text,jsonb)` | Tạo pending và trả thông tin yêu cầu, thử lại cùng UUID không tạo trùng |

Migration được tạo bằng Supabase CLI và lưu tại
`database/20261109165740_student_request_foundation.sql`.

Server lấy danh tính từ JWT; không tin role, student_id, phòng hay trạng thái do
Flutter cung cấp. Các RPC chỉ cấp EXECUTE cho authenticated, pin search_path rỗng
và kiểm tra Sinh viên active/đã đổi mật khẩu. Không cấp INSERT/UPDATE/DELETE các
bảng nghiệp vụ trực tiếp cho ứng dụng.

Ảnh tạm có đường dẫn
`student-requests/{uid}/{request_id}/{photo_id}.{extension}`. Ba policy mới chỉ cho
upload/đọc/xóa ảnh tạm của chính tài khoản, tối đa 5 ảnh mỗi lần. Finalize kiểm tra
owner, MIME, kích thước và danh sách object khớp manifest; ảnh đã liên kết không
được cleanup xóa. Bucket vẫn private và giữ giới hạn 5 MiB hiện có. Flutter kiểm
tra chữ ký định dạng bytes; SQL kiểm tra metadata đã được Storage ghi nhận.

## Thử lại khi mất mạng

UUID được giữ nguyên qua các lần thử lại cùng bản nhập khi form/lần gửi còn sống
trong RAM. Chưa lưu bản nháp hoặc UUID xuống thiết bị để phục hồi sau khi đóng
form hay khởi động lại app; trường hợp đó cần đối chiếu danh sách trên server
trước khi tạo yêu cầu mới. Server lưu SHA-256 của
payload tạo gốc vào `student_creation_fingerprint`, không lưu bản nội dung cũ.
Gửi lại cùng UUID/payload trả về yêu cầu đã có và không thêm lịch sử tạo lần nữa,
kể cả khi Admin đã đổi trạng thái. Payload khác cùng UUID bị từ chối.

Nếu chưa biết RPC có commit hay không, giao diện khóa bản nhập và chỉ cho kiểm tra
lại cùng lần gửi hoặc quay về danh sách để đối chiếu. Repository thử lại finalize
trước khi đụng Storage; không xóa ảnh khi kết quả commit chưa rõ. Upload blob và
giao dịch SQL là hai bước riêng; cleanup lỗi rõ ràng được giới hạn bằng policy.

## Demo Phần 1

1. Đăng nhập Sinh viên, xem dữ liệu từ Supabase và thử bộ lọc trạng thái.
2. Tạo yêu cầu với tiêu đề, loại, mô tả và ảnh; phòng chỉ đọc.
3. Ghi lại mã DF, mở chi tiết và phóng to ảnh.
4. Đăng xuất/đăng nhập lại: yêu cầu và ảnh vẫn còn.
5. Đăng nhập Admin → Yêu cầu, tìm đúng mã DF và mở chi tiết/ảnh tương ứng.
6. Dùng các yêu cầu cũ để xem kết quả, phản hồi và lịch sử đã lưu.

Kết quả nghiệm thu/test cụ thể được ghi trong `database/DEPLOYMENT.md`. Kịch bản
phân công → KTV xử lý → Sinh viên xác nhận hoàn tất được kiểm tra ở
[Phần 2](student-result-actions-contract.md); Phần 1 không tự
thay đổi trạng thái để làm dữ liệu demo trông như đã hoàn tất.
