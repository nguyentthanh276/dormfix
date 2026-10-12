# Database local DormFix

Schema đang dùng: app/assets/database/schema.sql. LocalDatabase tải asset và tạo đủ 10 bảng trong onCreate; không chạy SQL thủ công trên Supabase. Version database hiện là 1, file dormfix.db trong vùng dữ liệu riêng của ứng dụng Android.

Khác PostgreSQL: ID hồ sơ/phòng và bản ghi phụ là TEXT; ID repair_requests là INTEGER AUTOINCREMENT. Trigger tự đặt request_code DF000001 theo ID, có thể có khoảng trống; không tự đặt lại số. Khi mở lại yêu cầu, giữ bản ghi và mã cũ. Boolean là 0/1, thời gian là chuỗi UTC ISO, role/status dùng TEXT + CHECK. profiles chứa password_hash/password_salt/password_iterations thay liên kết auth.users.

Khóa ngoại bật bằng PRAGMA foreign_keys=ON. Các service ghi nhiều bảng phải dùng một transaction. SQL không thay thế mọi kiểm tra nghiệp vụ: service cần kiểm tra tài khoản, role, trạng thái, quyền sở hữu và điều kiện thao tác theo backlog. Không gọi database từ màn hình.

Email, mã định danh và role đã được trigger chặn chỉnh sửa. Seed chỉ tạo lần đầu; phiên đăng nhập ở RAM nên đóng app sẽ phải đăng nhập lại nhưng dữ liệu vẫn còn. 3 tài khoản demo/phòng/danh mục nằm trong app/lib/core/database/demo_seed.dart. Mật khẩu demo được lưu dạng hash có salt riêng.

Ảnh lưu trong thư mục documents của app qua LocalImageStore; request_attachments.storage_path sẽ lưu đường dẫn tương đối. Utility ảnh chưa tự ghi metadata, chưa kiểm tra quyền yêu cầu; việc này thuộc service nghiệp vụ tiếp theo.

Không tự tăng version hoặc xóa dormfix.db khi cập nhật app: cần migration giữ dữ liệu. onUpgrade hiện cố ý dừng nếu chưa có migration. Gỡ app hoặc Clear data sẽ mất dữ liệu local và seed được tạo lại ở lần chạy tiếp theo.

legacy_supabase/ giữ toàn bộ mã cloud trước chuyển đổi. Không chạy các file đó cho bản local.
