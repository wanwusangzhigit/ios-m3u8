#!/usr/bin/env python3
"""选择可用的 iPad 模拟器名称（供 xcodebuild test 使用）。

用法：python3 scripts/ci/select_ipad.py
输出：第一个可用 iPad 模拟器的名称（找不到则退出码 1）
"""
import json
import subprocess
import sys


def main() -> int:
    out = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        capture_output=True,
        text=True,
        check=False,
    )
    if out.returncode != 0:
        print("无法列出模拟器：", out.stderr, file=sys.stderr)
        return 1
    data = json.loads(out.stdout)
    for _runtime, devices in data.get("devices", {}).items():
        for device in devices:
            if "iPad" in device.get("name", "") and device.get("isAvailable"):
                print(device["name"])
                return 0
    print("未找到可用的 iPad 模拟器", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
