# Hợp đồng backend đăng nhập — cụm 1 (An)

Đã triển khai `get_my_profile()` trên Supabase ngày 12/10/2026. Phần 6 bổ sung bước hoàn tất đổi mật khẩu bắt buộc và đã kiểm thử bằng Flutter SDK trên Supabase ngày 10/11/2026.

## get_my_profile()

Không nhận user_id hay role từ Flutter. Hàm lấy người gọi từ auth.uid(); chỉ authenticated được gọi. Trả JSON object.

```dart
final supabase = Supabase.instance.client;
await supabase.auth.signInWithPassword(email: email, password: password);
final profile = Map<String, dynamic>.from(
  await supabase.rpc('get_my_profile'),
);
```

Thứ tự xử lí:

1. status là locked/revoked: báo tài khoản bị khóa/thu hồi và đăng xuất. Phản hồi chỉ có id, status, can_access=false và must_change_password; không đọc các trường role/email/name trong trường hợp này.
2. status=active, must_change_password=true: mở màn hình đổi mật khẩu; chưa vào nghiệp vụ.
3. status=active, can_access=true: điều hướng theo role admin/student/technician.
4. PROFILE_NOT_FOUND (P0002): báo chưa có hồ sơ và đăng xuất; không mặc định role.
5. AUTH_REQUIRED (28000) hoặc phiên hết hạn: yêu cầu đăng nhập lại. Mất mạng/lỗi dịch vụ: cho thử lại, không tự cho vào nghiệp vụ.

Khi active, phản hồi có id, identity_code, full_name, email, phone (có thể null), role, status, room (object hoặc null), must_change_password, can_access. room gồm id/code/building/is_active. Với Sinh viên mới dùng mật khẩu tạm, `role=student`, `room` là phòng Admin chọn, `must_change_password=true` và `can_access=false`.

## Đổi mật khẩu lần đầu

1. Flutter dùng `auth.updateUser` để đổi mật khẩu trong Supabase Auth.
2. `complete_change_password()` lấy hồ sơ của người gọi và kiểm tra tài khoản đang hoạt động. Máy chủ so dấu vân tay băm của mật khẩu hiện tại với dấu vân tay được ghi khi tạo tài khoản. Nếu hai giá trị trùng nhau hoặc thiếu bằng chứng, quyền vẫn bị chặn.
3. Khi xác nhận thành công, RPC gỡ cờ `must_change_password` và xóa dấu vân tay trong một giao dịch. Flutter đọc lại `get_my_profile()` trước khi điều hướng theo vai trò, kể cả khi mất phản hồi RPC.

Luồng trên áp dụng cho tài khoản được tạo hoặc đặt lại mật khẩu tạm từ tab Tài khoản của Admin. Dấu vân tay nằm trong schema riêng. RPC nghiệp vụ kiểm tra tài khoản active và cờ đổi mật khẩu. [Migration Phần 6](../database/20261109191056_admin_account_provisioning.sql) · [Migration Phần 7](../database/20261109194250_admin_account_lifecycle.sql)

## Phiên sau khi Admin đổi trạng thái hoặc đặt lại mật khẩu

- Khóa và thu hồi chặn đăng nhập ở Supabase Auth. Mở khóa hoặc khôi phục cho phép tạo phiên mới. Các thao tác này giữ cờ đổi mật khẩu nếu tài khoản đang dùng mật khẩu tạm.
- Đặt lại mật khẩu thay mật khẩu trong Auth, thu hồi các phiên cũ và đặt lại cờ `must_change_password` cho cùng tài khoản. Khi tài khoản đang khóa, người dùng vẫn cần Admin mở khóa trước khi đăng nhập.
- Data API kiểm tra phiên đã bị thu hồi trước khi chạy RPC. Bucket ảnh riêng kiểm tra cùng điều kiện qua RLS. Luồng tải hồ sơ yêu cầu đăng nhập lại khi API trả `ACCOUNT_SESSION_REVOKED`.
