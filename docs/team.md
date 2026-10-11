# Phân công theo backlog mới nhất

Phân công được chốt ngày 09/10/2026. Nguồn: [Backlog DormFix](https://docs.google.com/spreadsheets/d/1wyGEBfdeK9rxBVrfjD1VsaUn0o8sIh2cBu0Tgy27YfY/edit).

| Cụm | Thành viên | Nội dung phụ trách | Mã backlog | Số chức năng | Thư mục chính |
|---|---|---|---|---:|---|
| 1 | An | Đăng nhập, đăng xuất, đổi mật khẩu; hồ sơ và cập nhật số điện thoại Sinh viên/Kỹ thuật viên | DF-001–006, DF-018–019 | 8 | auth, profile |
| 2 | Tuyền | Sinh viên tạo, xem, lọc, chỉnh sửa, hủy yêu cầu; danh sách chờ xác nhận và thông báo | DF-007–013, DF-017 | 8 | student_requests; danh sách chờ xác nhận trong student_confirmation; thông báo Sinh viên trong notifications |
| 3 | Quỳnh | Sinh viên xác nhận sửa chữa, yêu cầu sửa lại, mở lại yêu cầu; Admin quản lí phòng và loại sự cố | DF-014–016, DF-039–042, DF-049–050 | 9 | thao tác xác nhận/sửa lại/mở lại trong student_confirmation, admin_rooms, incident_categories |
| 4 | Thành | Kỹ thuật viên xem/lọc công việc, bắt đầu/tiếp tục, nhận chuyển giao, gửi kết quả; lịch sử và thông báo | DF-020–027 | 8 | technician_jobs; thông báo Kỹ thuật viên trong notifications |
| 5 | Tánh | Admin tạo/cập nhật tài khoản, khóa/mở khóa, thu hồi, khôi phục và đặt lại mật khẩu | DF-031–038 | 8 | thao tác tạo/cập nhật/quản trị trong admin_accounts |
| 6 | Tài | Admin xem/tìm kiếm/lọc tài khoản; xem/lọc yêu cầu, phân công, từ chối, đổi Kỹ thuật viên và xác nhận thay Sinh viên | DF-028–030, DF-043–048 | 9 | danh sách/tìm kiếm/lọc trong admin_accounts, admin_requests |

Tổng cộng 50 chức năng; mỗi mã được giao cho đúng một thành viên. Chi tiết và quy tắc nghiệp vụ theo cột Function/Screen Details trong backlog.

## Phối hợp các phần dùng chung

- Tài và Tánh cùng dùng admin_accounts: Tài làm danh sách/tìm kiếm/lọc, Tánh làm tạo/cập nhật/quản trị. Thống nhất model và repository trước khi viết màn hình.
- Tuyền và Quỳnh cùng dùng student_confirmation: Tuyền làm danh sách chờ xác nhận, Quỳnh làm các thao tác xác nhận/sửa lại/mở lại. Không giao trùng DF-013.
- Tuyền và Thành cùng dùng notifications, tách phần trình bày theo role khi cần và dùng chung hợp đồng dữ liệu.
- An phụ trách đăng nhập và hồ sơ, phối hợp các thành viên khi nối điều hướng theo role.
- Thay đổi core, shared, app, schema và hợp đồng backend phải trao đổi trong nhóm trước để tránh trùng việc. Quyền truy cập và chuyển trạng thái cần được kiểm tra phía server.

## Checklist bắt đầu code

- [x] Tạo repository GitHub và cấu trúc Flutter Android/Web.
- [x] Chốt backlog 50 chức năng và phân công 6 cụm.
- [x] Triển khai schema Supabase: 10 bảng bật RLS và 4 loại sự cố; xem [kết quả triển khai](../database/DEPLOYMENT.md).
- [ ] Mời các thành viên vào GitHub, clone repository và chạy màn hình khởi động.
- [ ] Cung cấp cấu hình Supabase dùng cho ứng dụng qua config/local.json.
- [ ] Chốt danh sách màn hình và luồng điều hướng từng role.
- [ ] Triển khai các hàm backend, endpoint hồ sơ và quyền truy cập Storage; chốt dữ liệu đầu vào/đầu ra.
- [x] Tạo và xác minh tài khoản/hồ sơ demo Admin, Sinh viên và Kỹ thuật viên; xem [hướng dẫn demo](../database/DEMO_ACCOUNTS.md).
- [ ] An triển khai đăng nhập, kiểm tra account_status/must_change_password và điều hướng theo profile phía server.
- [ ] Làm luồng mẫu: tạo yêu cầu → phân công → sửa chữa → gửi kết quả → xác nhận.

Nhóm có thể dựng giao diện trong khi hoàn thiện backend. Khởi tạo SDK Supabase thành công chưa có nghĩa các thao tác nghiệp vụ đã sẵn sàng.
