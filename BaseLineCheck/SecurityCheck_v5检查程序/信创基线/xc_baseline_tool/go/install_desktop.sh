#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TARGET_DIR="$HOME/Desktop"
DESKTOP_FILE="$TARGET_DIR/信创基线检查.desktop"

mkdir -p "$TARGET_DIR"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=信创基线检查
Comment=国产信创系统基线检查与设置
Exec=$ROOT_DIR/run_gui.sh
Terminal=false
Categories=Utility;Security;
EOF

chmod +x "$DESKTOP_FILE"

printf "已生成桌面快捷方式: %s\n" "$DESKTOP_FILE"
