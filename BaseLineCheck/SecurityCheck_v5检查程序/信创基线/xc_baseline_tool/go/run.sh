#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

map_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "unknown" ;;
  esac
}

bin_arch=$(map_arch)
if [ "$bin_arch" = "unknown" ]; then
  echo "不支持的架构: $(uname -m)" >&2
  exit 1
fi

BIN="$ROOT_DIR/xc-baseline-go-$bin_arch"
if [ ! -x "$BIN" ]; then
  echo "未找到可执行文件: $BIN" >&2
  if [ -t 1 ]; then
    read -r -p "按回车关闭..." _
  fi
  exit 1
fi

if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  "$BIN" --check
  exit 0
fi

export NO_AT_BRIDGE=1

show_message() {
  echo "$1"
}

launch_terminal() {
  local cmd="$1"
  if command -v mate-terminal >/dev/null 2>&1; then
    if mate-terminal -- bash -lc "$cmd"; then
      return 0
    fi
  fi
  if command -v x-terminal-emulator >/dev/null 2>&1; then
    if x-terminal-emulator -e bash -lc "$cmd"; then
      return 0
    fi
  fi
  if command -v gnome-terminal >/dev/null 2>&1; then
    if gnome-terminal -- bash -lc "$cmd"; then
      return 0
    fi
  fi
  if command -v konsole >/dev/null 2>&1; then
    if konsole -e bash -lc "$cmd"; then
      return 0
    fi
  fi
  if command -v deepin-terminal >/dev/null 2>&1; then
    if deepin-terminal -e bash -lc "$cmd"; then
      return 0
    fi
  fi
  if command -v ukui-terminal >/dev/null 2>&1; then
    if ukui-terminal -e bash -lc "$cmd"; then
      return 0
    fi
  fi
  if command -v xfce4-terminal >/dev/null 2>&1; then
    if xfce4-terminal -e bash -lc "$cmd"; then
      return 0
    fi
  fi
  if command -v xterm >/dev/null 2>&1; then
    if xterm -e bash -lc "$cmd"; then
      return 0
    fi
  fi
  return 1
}

run_menu_in_terminal() {
echo "信创基线工具"
echo "-----------------------------"
echo "回车: 立即检查"
echo "1) 仅检查"
echo "2) 查看检查项"
echo "0) 退出"
echo -n "请选择: "
read -r choice
case "$choice" in
  "") "$BIN" --check ;;
  1) "$BIN" --check ;;
  2) "$BIN" --list ;;
  0) exit 0 ;;
  *) echo "无效选择" ;;
esac
  echo
  read -r -p "按回车关闭..." _
}

run_menu() {
  run_menu_in_terminal
}

run_menu
