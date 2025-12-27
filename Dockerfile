# Sử dụng image chính chủ mà bạn cung cấp
FROM traffmonetizer/cli_v2:latest

# Thiết lập biến môi trường (Bạn sẽ điền Token thật vào đây hoặc trên Dashboard)
ENV TOKEN="your_token_here" \
    DEVNAME="back4app-device"

# Image gốc của Traffmonetizer thường dùng User root, ta giữ nguyên để tránh lỗi quyền
USER root

# Trong image cli_v2, file thực thi thường nằm ngay thư mục gốc hoặc /app
# Chúng ta sử dụng lệnh find để đảm bảo tìm đúng đường dẫn và chạy nó
ENTRYPOINT ["/bin/sh", "-c", "./Cli start accept --token ${TOKEN} --device-name ${DEVNAME}"]
