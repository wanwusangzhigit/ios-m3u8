#!/usr/bin/env python3
"""随机生成 1024x1024 应用图标（纯 Python 标准库，无第三方依赖）。

- 随机双色对角渐变背景 + 中心光晕
- 白色下载箭头图案（契合 M3U8 下载器主题）
- 输出 AppIcon-1024.png，并同步更新 AppIcon.appiconset/Contents.json

用法：python3 scripts/ci/generate_icon.py
"""
import json
import random
import struct
import sys
import zlib
from pathlib import Path

SIZE = 1024
ROOT = Path(__file__).resolve().parents[2]
ICONSET = ROOT / "iosm3u8" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
PNG_PATH = ICONSET / "AppIcon-1024.png"
CONTENTS_PATH = ICONSET / "Contents.json"


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def in_triangle(px: float, py: float, a, b, c) -> bool:
    """半平面法判断点是否在三角形内"""

    def sign(x1, y1, x2, y2, x3, y3):
        return (x1 - x3) * (y2 - y3) - (x2 - x3) * (y1 - y3)

    d1 = sign(px, py, a[0], a[1], b[0], b[1])
    d2 = sign(px, py, b[0], b[1], c[0], c[1])
    d3 = sign(px, py, c[0], c[1], a[0], a[1])
    has_neg = d1 < 0 or d2 < 0 or d3 < 0
    has_pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (has_neg and has_pos)


def is_arrow(px: float, py: float) -> bool:
    """下载箭头：竖杆 + 三角头 + 底部横条"""
    # 竖杆
    if 462 <= px <= 562 and 240 <= py <= 560:
        return True
    # 三角头（顶点朝下）
    if in_triangle(px, py, (342, 510), (682, 510), (512, 700)):
        return True
    # 底部横条
    if 262 <= px <= 762 and 740 <= py <= 800:
        return True
    return False


def write_png(path: Path, width: int, height: int, rgba: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # 8-bit RGBA
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter: None
        raw += rgba[y * stride:(y + 1) * stride]
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def update_contents_json() -> None:
    data = json.loads(CONTENTS_PATH.read_text(encoding="utf-8"))
    for img in data.get("images", []):
        img["filename"] = "AppIcon-1024.png"
    CONTENTS_PATH.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def main() -> int:
    rng = random.SystemRandom()
    # 随机主色（保证足够明亮，图标在白底/深底上都可见）
    def rand_color():
        return (rng.randint(60, 255), rng.randint(60, 255), rng.randint(60, 255))

    c1 = rand_color()
    c2 = rand_color()
    glow = rand_color()  # 中心光晕色

    buf = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            t = (x + y) / (2.0 * (SIZE - 1))
            r = lerp(c1[0], c2[0], t)
            g = lerp(c1[1], c2[1], t)
            b = lerp(c1[2], c2[2], t)
            # 中心光晕叠加
            dx = (x - SIZE / 2) / (SIZE / 2)
            dy = (y - SIZE / 2) / (SIZE / 2)
            dist = (dx * dx + dy * dy) ** 0.5
            if dist < 1.0:
                halo = 1.0 - dist
                r = lerp(r, glow[0], halo * 0.35)
                g = lerp(g, glow[1], halo * 0.35)
                b = lerp(b, glow[2], halo * 0.35)
            # 下载箭头（白色、轻微抗锯齿：按距形状边缘近似，直接硬边）
            if is_arrow(x, y):
                r, g, b = 255, 255, 255
            buf += bytes((int(r), int(g), int(b), 255))

    ICONSET.mkdir(parents=True, exist_ok=True)
    write_png(PNG_PATH, SIZE, SIZE, bytes(buf))
    update_contents_json()
    print(f"已生成随机图标：{PNG_PATH}")
    print(f"背景色：{c1} → {c2}，光晕：{glow}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
