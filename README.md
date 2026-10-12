# DormFix local — PRM393

Project Flutter chạy local trên **một Android Emulator hoặc điện thoại Android**. Cả ba role lần lượt dùng cùng database SQLite trên thiết bị đó. Không cần Supabase, server hay Internet cho đăng nhập và nghiệp vụ local. Lần đầu tải thư viện/build vẫn cần Internet.

## Chạy

Dùng Flutter 3.47.6 (Dart 3.13.5), Android SDK và JDK 21. Trên máy leader có emulator PRM393_API36.

```sh
git clone https://github.com/nguyentthanh276/dormfix.git
cd dormfix
git switch codex/local-sqlite
cd app
flutter pub get
flutter emulators
flutter emulators --launch PRM393_API36
flutter devices
flutter run -d <ANDROID_DEVICE_ID>
```

Các thành viên tạo emulator riêng và thay tên/ID theo máy. Không truyền dart-define, không cần local.json hoặc API key. Bản local hiện không hỗ trợ Chrome/iOS/macOS; Chrome hiển thị hướng dẫn dùng Android.

## Dữ liệu demo

Lần đầu mở app tự tạo 10 bảng, phòng DEMO-A101, bốn loại sự cố và ba tài khoản: admin@example.com, student@example.com, technican@example.com. Mật khẩu demo ban đầu do leader cung cấp riêng. Sinh viên/Kỹ thuật viên phải đổi mật khẩu lần đầu, Admin vào hồ sơ trực tiếp. Chỉ seed trong onCreate; mật khẩu mới, số điện thoại và lịch sử được giữ khi đóng/mở app. Mỗi thiết bị có database riêng, không đồng bộ với cloud hay máy khác.

## Đã triển khai

- Schema SQLite, seed, khóa ngoại, unique/check, mã DF tự tăng và trigger giữ email/mã/role không đổi.
- AuthService Dart: đăng nhập/đăng xuất, đọc hồ sơ, kiểm tra status và role, bắt buộc đổi mật khẩu, đổi mật khẩu chủ động và cập nhật số điện thoại.
- Mật khẩu hash PBKDF2 SHA256 120000 vòng với salt riêng; không lưu mật khẩu plaintext trong database.
- Giao diện đăng nhập, đổi mật khẩu, hồ sơ hiển thị đúng role. Đây chưa phải dashboard nghiệp vụ của từng role.
- LocalImageStore sao chép JPEG/PNG/WebP vào thư mục app, kiểm tra kích thước và số ảnh đầu vào. Chưa có form chọn ảnh hay lưu metadata theo yêu cầu; Service nghiệp vụ phải kiểm tra quyền/số ảnh đã có trước khi dùng.

## Phần nhóm viết tiếp

Các chức năng yêu cầu sửa chữa, phân công, gửi kết quả, xác nhận và quản trị chưa triển khai. Không có backend server: viết Service Dart trong features tương ứng, dùng AuthService.requireBusinessAccess và transaction SQLite. Xem [hợp đồng local](docs/auth-contract.md), [setup local](docs/local-setup.md), [phân công](docs/team.md).

```text
app/lib/app/             Root app và chọn màn hình theo phiên
app/lib/core/database/   Mở SQLite và tạo dữ liệu lần đầu
app/lib/core/security/   Hash và validate mật khẩu
app/lib/core/storage/    File ảnh local
app/lib/features/       Service, repository, model, màn hình theo chức năng
app/assets/database/    Schema SQLite đang chạy
database/               Hướng dẫn local và tài liệu cloud lưu trữ
docs/                   Hướng dẫn nhóm
```

## Kiểm tra

```sh
cd app
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

Cloud Supabase cũ không bị sửa hoặc xóa. Mã/tài liệu cũ được giữ trong database/legacy_supabase và docs/legacy_supabase để tham khảo; không dùng cho bản local. File Word hướng dẫn Supabase trước đây cũng thuộc phương án cũ.

Backlog giữ nguyên: [Backlog DormFix](https://docs.google.com/spreadsheets/d/1wyGEBfdeK9rxBVrfjD1VsaUn0o8sIh2cBu0Tgy27YfY/edit).
