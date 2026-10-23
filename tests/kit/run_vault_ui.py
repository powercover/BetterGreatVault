# Runs vault_ui_smoke.lua (UI.lua with EllesmereUI's vault skin mocked) from the addon folder.
import os
from lupa import LuaRuntime

here = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.environ.get("BGV_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))))
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(here, "vault_ui_smoke.lua"), encoding="utf-8").read())
