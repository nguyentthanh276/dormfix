# Hợp đồng backend đăng nhập — cụm 1 (An)

Đã triển khai trên Supabase ngày 12/10/2026, kiểm thử role trong SQL Editor đạt. Chưa kiểm thử từ phiên đăng nhập Flutter.

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

Khi active, phản hồi có id, identity_code, full_name, email, phone (có thể null), role, status, room (object hoặc null), must_change_password, can_access. room gồm id/code/building/is_active. Ví dụ Sinh viên trước đổi mật khẩu: email=student@example.com, role=student, room.code=DEMO-A101, must_change_password=true, can_access=false.

## Giới hạn hiện tại

RPC này chỉ đọc hồ sơ. Không cấp quyền cập nhật email/role/status hoặc tự đặt must_change_password=false. Các quyền đọc nghiệp vụ hiện có vẫn kiểm tra tài khoản active và đã đổi mật khẩu.

**Endpoint đổi mật khẩu bắt buộc chưa triển khai.** Không làm nút gọi updateUser rồi tự sửa flag, cũng không tạo RPC cho client khai rằng đã đổi mật khẩu. Bước tiếp theo cần endpoint server xác thực người gọi, kiểm tra mật khẩu, cập nhật Supabase Auth thành công rồi mới bỏ flag và ghi lịch sử. Không dùng auth.users.updated_at làm bằng chứng đổi mật khẩu vì trường này có thể đổi bởi thao tác khác.

Flutter vẫn là khung ứng dụng; đoạn trên là hợp đồng để An nối giao diện, chưa phải màn hình đăng nhập đã chạy.
