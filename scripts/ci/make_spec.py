#!/usr/bin/env python3
"""为 CI 生成剥离可选 ffmpeg-kit 依赖的工程定义 iosm3u8.ci.yml。

project.yml 中的 ffmpeg-kit framework 依赖为可选（未集成时应用通过
`#if canImport(FFmpegKit)` 自动降级为纯 TS 输出，不影响构建）。
CI 不下载该二进制，因此剥离依赖后交由 `xcodegen generate --spec` 使用。

用法：python3 scripts/ci/make_spec.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "project.yml"
DST = ROOT / "iosm3u8.ci.yml"

# 匹配 ffmpeg-kit 的注释块 + framework 条目（注释 6 空格缩进、embed 8 空格缩进）
FRAMEWORK_BLOCK = re.compile(
    r"\n {6}# ---.*?\n {6}- framework: Frameworks/FFmpegKit\.xcframework\n {8}embed: true",
    re.DOTALL,
)


def main() -> int:
    text = SRC.read_text(encoding="utf-8")
    stripped, count = FRAMEWORK_BLOCK.subn("", text)
    if count != 1:
        print(f"警告：预期剥离 1 处 ffmpeg-kit 依赖，实际 {count} 处", file=sys.stderr)
    DST.write_text(stripped, encoding="utf-8")
    print(f"已生成 {DST.name}（剥离 {count} 处 ffmpeg-kit 依赖）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
