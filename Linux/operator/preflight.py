# 本地预检检查串口库 Tk 和下载工具环境，供完整运行包启动前使用。
# 预检可导入后端并检查文件，不能把环境存在当作板卡已被识别。
# 源码交付未包含运行镜像，真正上板应使用已封存版本恢复出的完整演示工程。
"""Check local Python dependencies without accessing any board."""
import sys
from pathlib import Path
if sys.version_info < (3, 9):
    raise SystemExit('Python 3.9 or newer is required')
import tkinter  # noqa: F401
sys.path.insert(0, str(Path(__file__).resolve().parent))
import backend  # noqa: F401
print('Python, tkinter and bundled pyserial are available.')
