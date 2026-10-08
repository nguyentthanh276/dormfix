# Phân công theo backlog đã chốt

| Thành viên | Mã backlog | Thư mục chính |
|---|---|---|
| Tuyền | DF-001–006, DF-018–019, DF-028–030 | auth, profile; danh sách/tìm kiếm/lọc trong admin_accounts |
| Tánh | DF-007–012, DF-017 | student_requests; thông báo Sinh viên trong notifications |
| Quỳnh | DF-013–016, DF-039–042 | student_confirmation, admin_rooms |
| An | DF-031–038 | tạo/cập nhật/quản trị trong admin_accounts |
| Thành | DF-020–027 | technician_jobs; thông báo Kỹ thuật viên trong notifications |
| Tài | DF-043–050 | admin_requests, incident_categories |

Tuyền và An thống nhất các file trong admin_accounts trước khi làm. Tánh và Thành cùng dùng notifications, tách file theo role khi cần. Thay đổi core, shared và app phải trao đổi trong nhóm trước để tránh trùng việc. Phân công này giữ nguyên backlog.

## Bước tiếp theo

- [ ] Tất cả thành viên clone repository và chạy màn hình khởi động.
- [ ] Chốt danh sách màn hình và luồng điều hướng từng role.
- [ ] Kiểm tra/chạy migration trên Supabase và triển khai hàm server + RLS/Storage.
- [ ] Tạo tài khoản demo Admin, Sinh viên và Kỹ thuật viên.
- [ ] Tuyền triển khai đăng nhập, kiểm tra account_status/must_change_password và điều hướng theo profile phía server.
- [ ] Làm luồng mẫu: tạo yêu cầu → phân công → sửa chữa → gửi kết quả → xác nhận.
