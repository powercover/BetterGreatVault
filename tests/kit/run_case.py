# Runs case_smoke.lua (Case.lua's opening styles on a fake clock) from the addon folder.
import os
from lupa import LuaRuntime

here = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.environ.get("BGV_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))))
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(here, "case_smoke.lua"), encoding="utf-8").read())
