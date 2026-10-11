# DormFix — PRM393

Ứng dụng quản lí sửa chữa ký túc xá với ba vai trò: Admin, Sinh viên, Kỹ thuật viên.

## Hiện trạng

- Đã tạo khung Flutter cho Android và Web, theme chung và hỗ trợ tiếng Việt.
- Đã thêm Supabase SDK và cấu hình khởi tạo; chưa có khóa trong repository.
- Màn hình khởi động tạm thời chạy được khi chưa cấu hình Supabase. Khởi tạo SDK thành công không chứng minh database đã sẵn sàng.
- Chưa triển khai đăng nhập, phân quyền điều hướng hay các màn hình nghiệp vụ.
- `database/001_schema.sql` đã chạy trên Supabase ngày 12/10/2026: 10 bảng bật RLS và 4 loại sự cố. Đã có 3 tài khoản/hồ sơ demo và phòng DEMO-A101 (xem `database/DEMO_ACCOUNTS.md`); chưa có các hàm ghi nghiệp vụ và Storage policies. Kết quả tại `database/DEPLOYMENT.md`. Đọc `database/README.md` trước khi triển khai.

Backlog chính thức: [Backlog DormFix](https://docs.google.com/spreadsheets/d/1wyGEBfdeK9rxBVrfjD1VsaUn0o8sIh2cBu0Tgy27YfY/edit).

## Chạy project

Dùng Flutter **3.47.6**, Dart **3.13.5**, Android SDK và JDK 21 như môi trường khởi tạo. Chưa cấu hình iOS.

```sh
git clone https://github.com/nguyentthanh276/dormfix.git
cd dormfix/app
flutter pub get
flutter run -d chrome
```

Android: mở emulator trong Android Studio, chạy `flutter devices`, sau đó `flutter run -d <device-id>`.

### Cấu hình Supabase

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
    app/                 # Root app và điều hướng (sẽ bổ sung)
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
