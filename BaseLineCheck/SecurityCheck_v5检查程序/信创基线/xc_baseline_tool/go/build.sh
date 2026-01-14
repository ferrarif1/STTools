#!/usr/bin/env bash
set -euo pipefail

if ! command -v go >/dev/null 2>&1; then
  printf "缺少Go编译器，请先安装Go 1.20+。\n" >&2
  exit 1
fi

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

GOOS=${GOOS:-linux}
ARCHS=("amd64" "arm64")

for arch in "${ARCHS[@]}"; do
  CGO_ENABLED=0 GOOS=$GOOS GOARCH=$arch \
    go build -ldflags "-s -w" -o "$ROOT_DIR/xc-baseline-go-$arch" "$ROOT_DIR/main.go"
  printf "已生成静态单文件: %s\n" "$ROOT_DIR/xc-baseline-go-$arch"
done
