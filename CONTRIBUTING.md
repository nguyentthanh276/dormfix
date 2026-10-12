# Làm việc nhóm

1. Cập nhật main trước khi bắt đầu: `git switch main`, `git pull --ff-only`.
2. Tạo branch riêng, ví dụ `git switch -c codex/thanh-technician-jobs`.
3. Làm đúng mã backlog được giao; không tự đổi schema SQLite hoặc hợp đồng Service dùng chung.
4. Chạy format, analyze và test theo README trước khi commit.
5. Chọn file cụ thể với `git add <file>`, rồi `git commit -m "feat: ..."`.
6. Đẩy branch: `git push -u origin <ten-branch>`; tạo Pull Request vào main và nhờ một thành viên review.

Commit `pubspec.lock` để nhóm dùng cùng phiên bản thư viện. Không commit mật khẩu plaintext, file .db, ảnh demo hoặc dữ liệu cá nhân. Tên/email tác giả Git được từng người cấu hình trên máy mình.

CI kiểm tra Flutter khi push main hoặc mở Pull Request; branch protection cần chủ repository cấu hình riêng nếu muốn bắt buộc review/check.
