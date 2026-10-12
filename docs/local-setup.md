# Setup DormFix local cho thành viên

1. Cài Flutter 3.47.6, Android Studio/SDK, JDK 21 và Git. Tạo Android Emulator.
2. Clone repository; chuyển sang branch codex/local-sqlite (hoặc main khi PR này đã được merge).
3. Mở thư mục app, chạy flutter pub get.
4. Mở emulator, chạy flutter devices rồi flutter run -d <ANDROID_DEVICE_ID>.
5. App tự tạo dữ liệu local khi mở lần đầu. Đăng nhập tài khoản demo bằng mật khẩu leader cung cấp.
6. Sinh viên/Kỹ thuật viên phải đổi mật khẩu trước khi vào hồ sơ. Admin vào hồ sơ trực tiếp.
7. Đóng/mở app để kiểm tra mật khẩu đã đổi còn hiệu lực. Không xóa dữ liệu giữa các vai trò khi demo.

Không cần API key, local.json, Supabase Dashboard hoặc Internet khi sử dụng nghiệp vụ. Flutter pub get và lần build đầu cần Internet. Không dùng flutter run -d chrome vì bản SQLite này chọn Android làm nền tảng demo.

Mỗi máy/thiết bị có dữ liệu riêng. Để demo luồng ba role, đăng xuất/đăng nhập lần lượt trên cùng emulator. Phần nghiệp vụ chưa hoàn thành; hiện có đăng nhập, đổi mật khẩu và hồ sơ.

Khi báo review: mở main.dart → LocalDatabase → AuthService → LoginPage/PasswordPage/ProfilePage. Trình bày UI → Service Dart → Repository → SQLite → UI.

Các hướng dẫn Supabase và file Word trước đây là tài liệu của phương án cũ, không áp dụng cho bản local.
