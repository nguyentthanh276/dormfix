# Hướng dẫn cấu hình Supabase cho thành viên DormFix

Mục tiêu: chạy project Flutter trên máy của mỗi thành viên với database Supabase dùng chung của nhóm. Không tạo project Supabase mới và không chạy lại các file SQL trong database/.

## 1. Chuẩn bị mã nguồn

Leader cần cấp quyền truy cập repository GitHub cho thành viên. Nếu chưa tải project:

```sh
git clone https://github.com/nguyentthanh276/dormfix.git
cd dormfix/app
flutter pub get
```

Nếu đã tải, mở Terminal tại thư mục repository dormfix và cập nhật:

```sh
git pull --ff-only
cd app
flutter pub get
```

Project khởi tạo với Flutter 3.47.6 và Dart 3.13.5. Cài Flutter và Chrome để chạy Web trước; Flutter đã đi kèm Dart. Kiểm tra bằng flutter --version và flutter doctor.

## 2. Nhận cấu hình từ leader

Mọi thành viên dùng chung:

| Thông tin | Giá trị |
|---|---|
| Tên project | DormFix |
| Project URL | https://nxobutgnhceyabjbiiya.supabase.co |
| Publishable key | Leader cung cấp khóa của project |

Leader lấy khóa tại Supabase Dashboard → Project Settings → API Keys → Publishable key. Thành viên chỉ chạy ứng dụng không cần quyền quản trị Dashboard hoặc mật khẩu database.

Publishable key dùng cho ứng dụng; quyền truy cập dữ liệu vẫn do đăng nhập và RLS quyết định. Không dùng secret key hoặc service_role key trong Flutter, không gửi các khóa quản trị vào nhóm và không đưa mật khẩu vào Git.

Tham khảo: https://supabase.com/docs/guides/getting-started/api-keys

## 3. Tạo file cấu hình trên máy

Trong VS Code hoặc Android Studio:

1. Mở thư mục app/config.
2. Sao chép example.json và đặt tên bản sao là local.json.
3. Giữ nguyên Project URL, thay chuỗi rỗng của SUPABASE_PUBLISHABLE_KEY bằng khóa leader cung cấp.
4. Lưu file. Kiểm tra tên file là local.json, không phải local.json.txt.

Nội dung mẫu dưới đây chỉ là hướng dẫn; phải thay giá trị khóa trước khi chạy:

```json
{
  "SUPABASE_URL": "https://nxobutgnhceyabjbiiya.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "DIEN_PUBLISHABLE_KEY_LEADER_CUNG_CAP"
}
```

Không đổi tên hai trường cấu hình. Giữ dấu ngoặc kép và dấu phẩy như mẫu; không thêm chú thích trong JSON.

File local.json đã được .gitignore bỏ qua. Mỗi thành viên tự tạo file này; git clone hoặc git pull không tải file cấu hình cá nhân về.

## 4. Chạy ứng dụng

Mở Terminal tại thư mục app, nơi có pubspec.yaml:

```sh
flutter pub get
flutter run -d chrome --dart-define-from-file=config/local.json
```

Chạy Android: mở emulator trong Android Studio hoặc kết nối điện thoại đã bật USB debugging. Xem thiết bị và chạy:

```sh
flutter devices
flutter run -d <DEVICE_ID> --dart-define-from-file=config/local.json
```

Thay <DEVICE_ID> bằng ID hiển thị trong flutter devices.

Sau khi thay cấu hình, dừng lần chạy hiện tại và chạy lại lệnh đầy đủ. Hot reload không cập nhật các giá trị dart-define.

## 5. Kiểm tra kết quả

Khi cấu hình hợp lệ, ứng dụng sẽ kiểm tra session Supabase:

- Chưa đăng nhập: hiện form đăng nhập DormFix.
- Có session: gọi RPC `get_my_profile()` để kiểm tra quyền trước khi hiển thị placeholder theo role.
- Tài khoản cần đổi mật khẩu: chặn khu vực nghiệp vụ và yêu cầu liên hệ quản trị viên. Endpoint đổi mật khẩu bắt buộc chưa có.

Đăng nhập dùng tài khoản và mật khẩu do leader cung cấp. Việc khởi tạo SDK không đảm bảo khóa hợp lệ hoặc RPC hoạt động; nếu có lỗi, kiểm tra nội dung trên màn hình và cấu hình. Không sửa RLS để thử khắc phục lỗi cấu hình.

## 6. Dữ liệu demo dùng chung

| Vai trò | Email | Mã hồ sơ | Phòng |
|---|---|---|---|
| Admin | admin@example.com | ADMIN001 | Không áp dụng |
| Sinh viên | student@example.com | SV001 | DEMO-A101 |
| Kỹ thuật viên | technican@example.com | KTV001 | Không áp dụng |

Email technican@example.com được giữ đúng theo lựa chọn đã chốt của nhóm. Mật khẩu được leader cung cấp riêng, không ghi trong tài liệu hoặc mã nguồn. Email demo không nhận thư xác nhận/khôi phục mật khẩu; các tài khoản đã được xác nhận trên Dashboard.

Database đã có ba hồ sơ và bốn loại sự cố: Điện, Nước, Nội thất, Khác. Chưa có yêu cầu sửa chữa mẫu. Sinh viên và Kỹ thuật viên có must_change_password=true nên chưa được truy cập nghiệp vụ trước khi hoàn tất luồng đổi mật khẩu bắt buộc; endpoint đổi mật khẩu phía server chưa triển khai tại thời điểm soạn hướng dẫn.

Để nối đăng nhập và đọc hồ sơ, xem [hợp đồng backend](auth-contract.md). Các thành viên dựng màn hình có thể dùng dữ liệu mẫu cục bộ trong khi chờ backend nghiệp vụ.

Đây là database dùng chung: thao tác dữ liệu của một người có thể ảnh hưởng các thành viên khác. Không tự xóa bảng, chạy lại migration/seed hoặc đổi hồ sơ demo để bỏ qua cờ mật khẩu.

## 7. Xử lí lỗi thường gặp

| Lỗi | Cách xử lí |
|---|---|
| Không tìm thấy config/local.json | Tạo bản sao example.json; chạy lệnh từ thư mục app |
| JSON không hợp lệ | Kiểm tra dấu ngoặc kép, dấu phẩy; bỏ chú thích và dấu phẩy cuối |
| Chưa sẵn sàng kết nối dịch vụ | Kiểm tra cấu hình, truyền đủ tham số và chạy lại ứng dụng |
| Invalid API key / 401 | Xin lại Publishable key đúng project; không thay bằng secret key |
| Permission denied / dữ liệu rỗng | Kiểm tra đăng nhập, role, status và must_change_password; báo leader nếu quyền chưa triển khai |
| PROFILE_NOT_FOUND | Tài khoản Auth chưa có hồ sơ liên kết; nhờ leader kiểm tra |
| Chưa vào được form đăng nhập | Kiểm tra `config/local.json`, chạy đúng lệnh ở mục 4; nếu có session cũ, ứng dụng sẽ xác minh session trước |

## Checklist báo leader

- [ ] Đã tải hoặc cập nhật repository.
- [ ] Đã chạy flutter pub get thành công.
- [ ] Đã tạo app/config/local.json và điền cấu hình đúng project.
- [ ] Đã chạy ứng dụng với --dart-define-from-file.
- [ ] Đã thấy màn hình DormFix; hiểu rằng khởi tạo SDK chưa xác nhận kết nối dữ liệu đầy đủ.
