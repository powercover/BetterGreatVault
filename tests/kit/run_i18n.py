# Runs i18n_smoke.lua from the addon folder in lupa's default Lua (5.5).
import os
from lupa import LuaRuntime

here = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.environ.get("BGV_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))))
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(here, "i18n_smoke.lua"), encoding="utf-8").read())
