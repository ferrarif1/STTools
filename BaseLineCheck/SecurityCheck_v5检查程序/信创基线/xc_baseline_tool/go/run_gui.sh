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

have_zenity=false
have_kdialog=false
command -v zenity >/dev/null 2>&1 && have_zenity=true
command -v kdialog >/dev/null 2>&1 && have_kdialog=true

show_message() {
  local msg="$1"
  if $have_zenity; then
    zenity --info --title="信创基线" --text="$msg" >/dev/null 2>&1 || true
  elif $have_kdialog; then
    kdialog --msgbox "$msg" >/dev/null 2>&1 || true
  else
    echo "$msg"
  fi
}

show_result() {
  local content="$1"
  if $have_zenity; then
    printf "%s" "$content" | zenity --text-info --title="检查结果" --width=900 --height=600 >/dev/null 2>&1 || true
  elif $have_kdialog; then
    local tmp
    tmp=$(mktemp)
    printf "%s" "$content" > "$tmp"
    kdialog --textbox "$tmp" 900 600 >/dev/null 2>&1 || true
    rm -f "$tmp"
  else
    echo "$content"
  fi
}

run_check() {
  local output
  output=$("$BIN" --check 2>&1 || true)
  if $have_zenity || $have_kdialog; then
    show_result "$output"
  else
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

confirm_repair() {
  if $have_zenity; then
    if zenity --question --title="信创基线" --text="检查已完成。是否进行修复（应用全部可设置项）？" 2>/dev/null; then
      echo "y"
    else
      echo "n"
    fi
  elif $have_kdialog; then
    if kdialog --yesno "检查已完成。是否进行修复（应用全部可设置项）？" 2>/dev/null; then
      echo "y"
    else
      echo "n"
    fi
  else
    echo "n"
  fi
}

run_apply_all() {
  if command -v pkexec >/dev/null 2>&1; then
    pkexec "$BIN" --apply-all --ui || true
  else
    show_message "未检测到pkexec，无法自动提权。请联系管理员运行。"
  fi
}

if ! $have_zenity && ! $have_kdialog; then
  show_message "未检测到图形组件(zenity/kdialog)。将保存检查结果到桌面。"
fi

run_check
repair=$(confirm_repair)
if [ "$repair" = "y" ]; then
  run_apply_all
fi
