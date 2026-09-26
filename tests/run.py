import os
import sys
from pathlib import Path

from lupa import LuaRuntime

root = Path(__file__).resolve().parents[1]
os.chdir(root)
lua = LuaRuntime(unpack_returned_tuples=True)
script = (root / "tests" / "loot_refresh.lua").read_text(encoding="utf-8")
lua.execute(script)
sys.exit(0)
