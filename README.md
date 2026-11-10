# DormFix — PRM393

Ứng dụng quản lí sửa chữa ký túc xá với ba vai trò: Admin, Sinh viên, Kỹ thuật viên.

## Hiện trạng

- Giao diện ưu tiên điện thoại, header và bốn tab theo từng vai trò; xem [khung giao diện](docs/mobile-ui.md).
- Đăng nhập/đăng xuất, khôi phục phiên và điều hướng theo hồ sơ Supabase. Cấu hình máy nằm trong file được Git bỏ qua; không đưa secret/service_role key vào Flutter.
- Phần 1 DF-007–010 đã nối Supabase: Sinh viên tạo yêu cầu kèm ảnh private, xem danh sách chính chủ, lọc trạng thái và xem chi tiết. Đã kiểm tra tạo/đọc ảnh bằng Flutter SDK và Admin đọc cùng yêu cầu; xem [luồng chạy và demo](docs/student-requests-contract.md).
- Phần 2 DF-013/014/015 đã nối xác nhận/sửa lại vào Supabase. Luồng Admin phân công → KTV gửi kết quả → Sinh viên sửa lại → KTV tiếp tục/gửi kết quả mới → Sinh viên xác nhận hoàn tất đã qua kiểm tra bằng repository SDK thật; xem [hướng dẫn demo và review](docs/student-result-actions-contract.md).
- Phần 3 DF-011/012/016 đã triển khai lên Supabase ngày 10/11/2026. Sinh viên có thể sửa yêu cầu Chờ tiếp nhận, hủy trước khi KTV bắt đầu và mở lại yêu cầu Hoàn tất của phòng đang ở. Các nút xuất hiện theo quyền máy chủ trả về cho từng yêu cầu. [Migration Phần 3](database/20261109175550_student_request_lifecycle.sql)
- Phần 4 DF-017 đã triển khai thông báo cho Sinh viên khi Admin phân công hoặc từ chối. Tab Thông báo hiển thị số chưa đọc và mở đúng yêu cầu khi bấm vào thông báo. [Hợp đồng DF-017](docs/student-notifications-contract.md)
- Phần 5 DF-039–042/049–050 đã nối hai tab Phòng và Loại sự cố của Admin với Supabase. Sinh viên chỉ chọn loại đang hoạt động. Yêu cầu cũ giữ tên loại và phòng tại thời điểm ghi nhận. [Migration Phần 5](database/20261109185257_admin_rooms_and_categories.sql)
- Phần 6 DF-031–034 đã nối tab Tài khoản của Admin với Supabase để tạo và cập nhật Sinh viên, Kỹ thuật viên. Tài khoản mới phải đổi mật khẩu tạm khi đăng nhập lần đầu. [Luồng đăng nhập](docs/auth-contract.md)
- Phần 7 DF-035–038 bổ sung khóa, mở khóa, thu hồi, khôi phục và đặt lại mật khẩu tạm trong menu tài khoản của Admin. Supabase chặn phiên cũ sau các thao tác này. [Migration Phần 7](database/20261109194250_admin_account_lifecycle.sql)
- Phần 8 DF-043–048 nghiệm thu tab Yêu cầu của Admin, gồm phân công, từ chối, đổi Kỹ thuật viên và xử lý thay Sinh viên đã thu hồi. [Biên bản nghiệm thu](database/DEPLOYMENT.md)
- Hai migration `20261109165740_student_request_foundation.sql` và `20261109173649_student_result_confirmation.sql` đã triển khai ngày 10/11/2026. Kết quả và giới hạn xác minh tại [database/DEPLOYMENT.md](database/DEPLOYMENT.md). Đọc [hướng dẫn database](database/README.md) trước khi triển khai; không chạy lại migration đã áp dụng.

Backlog chính thức: [Backlog DormFix](https://docs.google.com/spreadsheets/d/1wyGEBfdeK9rxBVrfjD1VsaUn0o8sIh2cBu0Tgy27YfY/edit).

## Chạy project

Dùng Flutter **3.47.6**, Dart **3.13.5**, Android SDK và JDK 21 như môi trường khởi tạo. Chưa cấu hình iOS.

```sh
git clone https://github.com/nguyentthanh276/dormfix.git
cd dormfix/app
flutter pub get
flutter run -d <device-id> --dart-define-from-file=config/local.json
```

Android: mở emulator trong Android Studio, chạy `flutter devices` để lấy device ID. Cấu hình Supabase theo hướng dẫn bên dưới trước khi chạy dữ liệu thật. Có thể dùng `-d chrome` để kiểm tra bản Web.

### Cấu hình Supabase

Hướng dẫn từng bước cho thành viên: [docs/supabase-setup.md](docs/supabase-setup.md).

Sao chép `app/config/example.json` thành `app/config/local.json`, điền **publishable key** của project. File local được Git bỏ qua. Không đưa secret/service_role key vào Flutter.

Trong thư mục `app`:

```sh
flutter run -d chrome --dart-define-from-file=config/local.json
```

Cách khởi tạo theo [Supabase Flutter docs](https://supabase.com/docs/reference/dart/initializing). Cấu hình này chỉ khởi tạo SDK; database và quyền truy cập cần triển khai riêng.

## Cấu trúc

```text
app/
  lib/
    app/                 # Root app và điều hướng theo trạng thái xác thực
    core/                # Config, theme, enum dùng chung
    shared/widgets/      # Widget tái sử dụng
    features/            # Từng nhóm chức năng
      auth/
      profile/
      student_requests/
      student_confirmation/
      technician_jobs/
      admin_accounts/
      admin_rooms/
      admin_requests/
      incident_categories/
      notifications/
  config/                # File cấu hình mẫu; local.json không commit
  test/
database/                # SQL và ghi chú backend
docs/                    # Phân công và quy trình Git
.github/workflows/       # Kiểm tra tự động
```

Mỗi feature có `data/` (repository gọi Supabase), `models/` (dữ liệu), `presentation/` (màn hình/widget). Chỉ tạo file khi cần; thư mục hiện tại là khung, không phải chức năng đã hoàn thành. Quyền role và quy tắc chuyển trạng thái phải kiểm tra phía server; không ghi trực tiếp trạng thái yêu cầu từ UI.

## Kiểm tra trước khi gửi PR

```sh
cd app
dart format lib test
flutter analyze
flutter test
flutter build web
```

Theo dõi phân công tại [docs/team.md](docs/team.md), quy trình tại [CONTRIBUTING.md](CONTRIBUTING.md).
