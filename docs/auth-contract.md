# Hợp đồng Service local cho An và nhóm

Không gọi Supabase hoặc RPC. Root app tạo LocalDatabase → AuthRepository → AuthService; các màn hình dùng cùng instance AuthService. LoginPage, PasswordPage và ProfilePage hiện đã có bản nền tảng để An phát triển tiếp.

## API

- auth.login(email, password): kiểm tra hash và status, đăng nhập đúng tài khoản; email trim/lowercase nhưng mật khẩu giữ nguyên.
- auth.logout(): xóa phiên trong RAM. Không xóa database.
- auth.getMyProfile(): đọc lại hồ sơ chính chủ từ SQLite; chặn tài khoản locked/revoked và đăng xuất khi phiên không còn hợp lệ. Không lộ hash/salt trong UserProfile.
- auth.requireBusinessAccess(roles: {AppRole.student}): mỗi service nghiệp vụ phải gọi trước thao tác; chặn chưa đăng nhập, chưa đổi mật khẩu, sai role và tài khoản bị khóa/thu hồi.
- auth.changePassword(currentPassword, newPassword): validate, kiểm tra mật khẩu cũ, tạo hash/salt mới và bỏ must_change_password cùng transaction, ghi lịch sử.
- auth.updatePhone(phone): chính chủ Sinh viên/Kỹ thuật viên, đã đổi mật khẩu; chỉ cập nhật phone và lịch sử. Email/mã/role không sửa.

Ví dụ service tương lai:

```dart
final student = await auth.requireBusinessAccess(roles: {AppRole.student});
// Kiểm tra phòng và loại sự cố hoạt động; dùng student.id từ phiên.
// Trong database.transaction: ghi yêu cầu và lịch sử cùng nhau.
```

Màn hình gọi service; service gọi repository. Không dùng auth.current làm kiểm tra quyền duy nhất vì đó là bản hiển thị; requireBusinessAccess đọc lại trạng thái trong SQLite. Trong transaction phải kiểm tra các điều kiện có thể thay đổi và khóa/đọc dữ liệu tương ứng trước khi ghi.

## Điều hướng hiện có

Chưa đăng nhập → LoginPage. must_change_password=true → PasswordPage bắt buộc, không quay về nghiệp vụ. Sau đổi mật khẩu → ProfilePage hiển thị tên role. Khi role dashboards hoàn thành, nhóm thay nhánh ProfilePage bằng các dashboard tương ứng.

## Demo

admin@example.com / ADMIN001; student@example.com / SV001 / DEMO-A101; technican@example.com / KTV001. Mật khẩu ban đầu do leader cung cấp. Các tài khoản được tạo local, không dùng thông tin từ Supabase. Chỉ demo một thiết bị; kiểm tra quyền trong Dart phù hợp scope này, không phải hệ thống bảo mật server cho triển khai nhiều người dùng.
