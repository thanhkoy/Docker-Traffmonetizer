#!/bin/bash
set -e

BIN_SDK="/app/traffmonetizerCLI"
IP_CHECKER_URL="https://raw.githubusercontent.com/techroy23/IP-Checker/refs/heads/main/app.sh"
ENABLE_IP_CHECKER="${ENABLE_IP_CHECKER:-false}"
PROXY_TYPE="${PROXY_TYPE:-socks5}"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

if [ -z "${TOKEN:-}" ]; then
  log " >>> An2Kin >>> ERROR: TOKEN environment variable is not set."
  exit 1
fi

if [ -z "${DEVNAME:-}" ]; then
  log " >>> An2Kin >>> ERROR: DEVNAME environment variable is not set."
  exit 1
fi

setup_iptables() {
  log " >>> An2Kin >>> Setting up iptables and redsocks..."
  if ! iptables -t nat -L REDSOCKS -n >/dev/null 2>&1; then
    iptables -t nat -N REDSOCKS
  else
    iptables -t nat -F REDSOCKS
  fi
  iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
  iptables -t nat -A REDSOCKS -d $host -j RETURN
  iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports 12345

  if ! iptables -t nat -C OUTPUT -p tcp -j REDSOCKS 2>/dev/null; then
    iptables -t nat -A OUTPUT -p tcp -j REDSOCKS
  fi
}

cleanup() {
  log " >>> An2Kin >>> Cleaning up iptables and redsocks..."
  iptables -t nat -F REDSOCKS 2>/dev/null || true
  iptables -t nat -D OUTPUT -p tcp -j REDSOCKS 2>/dev/null || true
  iptables -t nat -X REDSOCKS 2>/dev/null || true
  kill $REDSOCKS_PID 2>/dev/null || true
}
trap cleanup EXIT

setup_proxy() {
  if [ -n "$PROXY" ]; then
    log " >>> An2Kin >>> External routing via proxy: $PROXY (Type: $PROXY_TYPE)"

    local user pass host port auth_fields redsocks_type

    if [[ "$PROXY" == *"@"* ]]; then
      # Định dạng: user:pass@host:port
      local credentials=$(echo "$PROXY" | cut -d@ -f1)
      local server=$(echo "$PROXY" | cut -d@ -f2)
      user=$(echo "$credentials" | cut -d: -f1)
      pass=$(echo "$credentials" | cut -d: -f2)
      host=$(echo "$server" | cut -d: -f1)
      port=$(echo "$server" | cut -d: -f2)
      auth_fields="login = \"$user\";\n  password = \"$pass\";"
    else
      # Định dạng: host:port
      host=$(echo "$PROXY" | cut -d: -f1)
      port=$(echo "$PROXY" | cut -d: -f2)
      auth_fields="" # Không có xác thực
    fi

    # Xác định loại proxy cho redsocks
    if [ "$PROXY_TYPE" = "https" ]; then
      redsocks_type="http-connect" # Dành cho proxy HTTPS (sử dụng phương thức CONNECT)
    elif [ "$PROXY_TYPE" = "socks5" ]; then
      redsocks_type="socks5"
    else
      log " >>> An2Kin >>> ERROR: Unsupported PROXY_TYPE: $PROXY_TYPE. Use 'socks5' or 'https'."
      return 1 # Trả về lỗi để ngăn tập lệnh tiếp tục
    fi

    # Tạo tệp cấu hình redsocks động
    cat >/etc/redsocks.conf <<EOF
base {
  log_debug = off;
  log_info = off;
  log = "stderr";
  daemon = off;
  redirector = iptables;
}

redsocks {
  local_ip = 0.0.0.0;
  local_port = 12345;
  
  # Thông tin máy chủ proxy
  ip = $host;
  port = $port;
  
  # Loại proxy và thông tin xác thực
  type = $redsocks_type;
  $auth_fields 
}
EOF

    redsocks -c /etc/redsocks.conf >/dev/null 2>&1 &
    REDSOCKS_PID=$!

    setup_iptables
  else
    log " >>> An2Kin >>> Proxy not set, proceeding with direct connection"
  fi
}

check_ip() {
  if [ "$ENABLE_IP_CHECKER" = "true" ]; then
    log " >>> An2Kin >>> Checking current public IP..."
    if curl -fsSL "$IP_CHECKER_URL" | sh; then
      log " >>> An2Kin >>> IP checker script ran successfully"
    else
      log " >>> An2Kin >>> WARNING: Could not fetch or execute IP checker script"
    fi
  else
    log " >>> An2Kin >>> IP checker disabled (ENABLE_IP_CHECKER=$ENABLE_IP_CHECKER)"
  fi
}

main() {
  while true; do
      # Báo lỗi nếu setup_proxy thất bại
      if ! setup_proxy; then
        log " >>> An2Kin >>> CRITICAL: Failed to set up proxy. Retrying in 30 seconds..."
        sleep 30
        continue # Bỏ qua vòng lặp này và thử lại
      fi
      
      check_ip
      log " >>> An2Kin >>> Starting binary..."
      "$BIN_SDK" start accept --token "$TOKEN" --device-name "$DEVNAME" status statistics &
      PID=$!
      log " >>> An2Kin >>> APP PID is $PID"
      wait $PID
      log " >>> An2Kin >>> Process exited, restarting..."
      sleep 5
  done
}

main
