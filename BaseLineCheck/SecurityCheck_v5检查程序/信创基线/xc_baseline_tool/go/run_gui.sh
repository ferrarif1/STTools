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
  exit 1
fi

show_message() {
  echo "$1"
}

launch_terminal() {
  local cmd="$1"
  if command -v x-terminal-emulator >/dev/null 2>&1; then
    x-terminal-emulator -e bash -lc "$cmd"
    return
  fi
  if command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal -- bash -lc "$cmd"
    return
  fi
  if command -v konsole >/dev/null 2>&1; then
    konsole -e bash -lc "$cmd"
    return
  fi
  if command -v deepin-terminal >/dev/null 2>&1; then
    deepin-terminal -e bash -lc "$cmd"
    return
  fi
  if command -v ukui-terminal >/dev/null 2>&1; then
    ukui-terminal -e bash -lc "$cmd"
    return
  fi
  if command -v xfce4-terminal >/dev/null 2>&1; then
    xfce4-terminal -e bash -lc "$cmd"
    return
  fi
  if command -v xterm >/dev/null 2>&1; then
    xterm -e bash -lc "$cmd"
    return
  fi
  return 1
}

run_menu() {
  local cmd
  cmd=$'echo \"信创基线工具\";\\\n'\
$'echo \"-----------------------------\";\\\n'\
$'echo \"回车: 立即检查\";\\\n'\
$'echo \"1) 检查并按提示修复\";\\\n'\
$'echo \"2) 仅检查\";\\\n'\
$'echo \"3) 查看检查项\";\\\n'\
$'echo \"0) 退出\";\\\n'\
$'echo -n \"请选择: \"; read -r choice;\\\n'\
$'case \"$choice\" in\\\n'\
$'  \"\") '$BIN' --check ;;\\\n'\
$'  1) '$BIN' --check-fix ;;\\\n'\
$'  2) '$BIN' --check ;;\\\n'\
$'  3) '$BIN' --list ;;\\\n'\
$'  0) exit 0 ;;\\\n'\
$'  *) echo \"无效选择\" ;;\\\n'\
$'esac;\\\n'\
$'echo; read -r -p \"按回车关闭...\" _'

  if ! launch_terminal "$cmd"; then
    show_message "未检测到终端模拟器，无法交互。将仅保存检查结果。"
    local output
    output=$("$BIN" --check 2>&1 || true)
    local ts
    ts=$(date +"%Y%m%d_%H%M%S" 2>/dev/null || echo "result")
    local result_file="$HOME/Desktop/基线检查结果_${ts}.txt"
    printf "%s\n" "$output" > "$result_file"
    if command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$result_file" >/dev/null 2>&1 || true
    fi
    echo "检查结果已保存: $result_file"
  fi
}

run_menu
