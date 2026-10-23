"""Runs a scratchpad smoke test (or several, as one chunk) on Lua 5.1, WoW's own Lua, from the addon folder.

python run51.py case_smoke.lua
python run51.py db_smoke.lua ui_smoke.lua
"""
import os
import sys

from lupa.lua51 import LuaRuntime

here = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.environ.get("BGV_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))))
lua = LuaRuntime(unpack_returned_tuples=True)
# The smoke tests were written on 5.4+: give them the few 5.2+ names they use (the addon's files
# get nothing extra: they run as they would in game).
lua.execute(r"""
table.unpack = table.unpack or unpack
table.pack = table.pack or function(...) return { n = select("#", ...), ... } end
utf8 = utf8 or { len = function(s) local _, n = string.gsub(s, "[^\128-\191]", "") return n end }
""")
source = "\n".join(open(os.path.join(here, name), encoding="utf-8").read() for name in sys.argv[1:])
lua.execute(source)
