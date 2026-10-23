"""Runs one of the repo's Python test scripts (tests/scenarios.py, tests/run.py, claim_reel_test.py) on
Lua 5.1, WoW's own Lua: lupa's default runtime is swapped for lupa.lua51 before the script imports it.

python py51.py tests/scenarios.py [args...]     (paths relative to BGV_ROOT, or absolute)
"""
import os
import runpy
import sys

import lupa
import lupa.lua51

lupa.LuaRuntime = lupa.lua51.LuaRuntime
lupa.LuaError = lupa.lua51.LuaError
lupa.LuaSyntaxError = lupa.lua51.LuaSyntaxError

root = os.environ.get("BGV_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
script = sys.argv[1]
if not os.path.isabs(script):
    script = os.path.join(root, script) if os.path.exists(os.path.join(root, script)) \
        else os.path.join(os.path.dirname(os.path.abspath(__file__)), script)
sys.argv = [script] + sys.argv[2:]
sys.path.insert(0, os.path.dirname(script))
runpy.run_path(script, run_name="__main__")
