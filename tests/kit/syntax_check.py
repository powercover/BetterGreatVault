"""Compiles every Lua file of the addon and reports real syntax errors (loadfile's error message)."""
import glob
import os
from lupa import LuaRuntime

os.chdir(os.environ.get("BGV_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))))
lua = LuaRuntime()
check = lua.eval("function(path) local chunk, err = loadfile(path) if chunk then return nil end return err end")
files = sorted(glob.glob("*.lua") + glob.glob("Locales/*.lua"))
errors = [(path, check(path)) for path in files]
errors = [(path, err) for path, err in errors if err]
for path, err in errors:
    print("SYNTAX ERROR", err)
print(f"syntax: {len(files)} files, {len(errors)} errors")
