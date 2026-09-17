#!/usr/bin/env bash
# 构建脚本：使用 DevEco Studio 自带工具链（node + hvigorw）执行 hvigor 任务。
# 用法: bash scripts/build.sh [assembleHap|clean|test]
# 可用环境变量覆盖: DEVECO_HOME(默认 /d/local/devecostudio)、DEVECO_SDK_HOME(默认 D:\local\devecostudio\sdk)
set -euo pipefail
cd "$(dirname "$0")/.."

TASK="${1:-assembleHap}"
DEVECO_HOME="${DEVECO_HOME:-/d/local/devecostudio}"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-D:\\local\\devecostudio\\sdk}"
export NODE_HOME="$DEVECO_HOME/tools/node"
export PATH="$NODE_HOME:$PATH"

HVIGORW_JS="$DEVECO_HOME/tools/hvigor/bin/hvigorw.js"
if [ ! -f "$HVIGORW_JS" ]; then
  echo "未找到 hvigorw: $HVIGORW_JS" >&2
  exit 1
fi

exec "$NODE_HOME/node.exe" "$HVIGORW_JS" --no-daemon "$TASK"
