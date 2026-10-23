# Runs db_smoke.lua's mocks followed by ui_smoke.lua as one chunk, from the addon folder, in lupa's default Lua (5.5).
import os
from lupa import LuaRuntime

here = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.environ.get("BGV_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))))
lua = LuaRuntime(unpack_returned_tuples=True)
src = "\n".join(open(os.path.join(here, f), encoding="utf-8").read() for f in ("db_smoke.lua", "ui_smoke.lua"))
lua.execute(src)
