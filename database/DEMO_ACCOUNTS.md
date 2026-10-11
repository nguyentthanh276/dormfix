# Tài khoản demo DormFix

## Bước cần người dùng thực hiện trên Dashboard

Vào Authentication → Users → Add user → Create new user. Tạo:

- admin@example.com
- student@example.com
- technican@example.com

Nhập mật khẩu đã thống nhất trực tiếp trên Dashboard; không ghi mật khẩu vào Git. Chọn Auto Confirm User để dùng email demo không có hộp thư. Không dùng Invite user vì email demo không nhận được thư. Giữ tính năng tự đăng kí của ứng dụng ở trạng thái tắt.

## Liên kết hồ sơ

Sau khi đủ ba Auth users đã xác nhận, chạy `002_demo_profiles.sql` bằng SQL Editor của project phát triển. Script dừng nếu thiếu user hoặc trùng hồ sơ/mã định danh; không tự thay đổi tài khoản cũ.

Script tạo phòng DEMO-A101, Admin Demo (ADMIN001), Sinh viên Demo (SV001), Kỹ thuật viên Demo (KTV001). Hai số điện thoại 0000000001 và 0000000002 chỉ là dữ liệu giả cho demo.

Admin dùng mật khẩu do leader tự đặt, must_change_password=false. Sinh viên/Kỹ thuật viên có must_change_password=true: chỉ dùng nghiệp vụ sau khi luồng đổi mật khẩu bắt buộc được triển khai và server xác nhận hoàn tất.

Tạo Auth user và profile chưa đồng nghĩa ứng dụng đã có đăng nhập/đổi mật khẩu. Flutter và endpoint hồ sơ vẫn cần triển khai tiếp.

Đã triển khai và xác minh ngày 12/10/2026: đủ ba Auth users xác nhận email, ba profiles liên kết đúng ID/email và phòng DEMO-A101 cho Sinh viên. Không chạy lại seed trên project hiện tại. Email technican@example.com được giữ theo xác nhận của leader. Chưa kiểm thử đăng nhập bằng mật khẩu hoặc quyền RLS theo phiên từng role.
