"""WoW's own Lua (5.1): compiles every addon file, then reads the bytecode for global reads and writes.

- A syntax error, or a limit WoW enforces (200 active locals per function, 60 upvalues per
  function: Lua 5.2+ allows 255, so the 5.5 check can't see it), fails the run.
- Every global the files write must be in ALLOWED_WRITES (anything else is a missing `local`).
- Every global they read is compared with the baseline file (lua51_globals.txt): a new name is
  usually a typo or a local that lost its declaration. `--update` rewrites the baseline.
- Headroom: each file's peak active locals in one function and its most upvalues in one function.

python lua51_lint.py [--root DIR] [--update]
"""
import glob
import os
import struct
import sys

from lupa.lua51 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("BGV_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
args = sys.argv[1:]
if "--root" in args:
    ROOT = args[args.index("--root") + 1]
UPDATE = "--update" in args
BASELINE = os.path.join(HERE, "lua51_globals.txt")

# Globals the addon is meant to create: saved variables, key bindings, slash commands.
ALLOWED_WRITES_PREFIXES = ("BINDING_", "SLASH_")
ALLOWED_WRITES = {"BetterGreatVaultDB", "BetterGreatVaultCharDB", "BetterGreatVault_OnBinding",
                  "BetterGreatVault_OnAddonCompartmentClick", "BetterGreatVault_OnAddonCompartmentEnter",
                  "BetterGreatVault_OnAddonCompartmentLeave"}

GETGLOBAL, SETGLOBAL = 5, 7


class Reader:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def take(self, n):
        chunk = self.data[self.pos:self.pos + n]
        self.pos += n
        return chunk

    def byte(self):
        return self.take(1)[0]

    def header(self):
        head = self.take(12)
        assert head[:4] == b"\x1bLua" and head[4] == 0x51, head
        self.int_size, self.size_t, self.ins_size, self.num_size = head[7], head[8], head[9], head[10]
        self.int_fmt = "<i" if self.int_size == 4 else "<q"
        self.size_fmt = "<Q" if self.size_t == 8 else "<I"

    def int(self):
        return struct.unpack(self.int_fmt, self.take(self.int_size))[0]

    def size(self):
        return struct.unpack(self.size_fmt, self.take(self.size_t))[0]

    def string(self):
        n = self.size()
        return self.take(n)[:-1].decode("utf-8", "replace") if n else None

    def function(self, out, depth=0):
        source = self.string()
        line_defined = self.int()
        self.int()  # last line
        nups, nparams, _, _ = self.take(4)
        code = [struct.unpack("<I", self.take(4))[0] for _ in range(self.int())]
        constants = []
        for _ in range(self.int()):
            kind = self.byte()
            if kind == 0:
                constants.append(None)
            elif kind == 1:
                constants.append(bool(self.byte()))
            elif kind == 3:
                constants.append(struct.unpack("<d", self.take(self.num_size))[0])
            elif kind == 4:
                constants.append(self.string())
            else:
                raise ValueError("constant type %d" % kind)
        children = []
        for _ in range(self.int()):
            children.append(self.function(out, depth + 1))
        lines = [self.int() for _ in range(self.int())]
        locvars = []
        for _ in range(self.int()):
            name = self.string()
            locvars.append((name, self.int(), self.int()))
        for _ in range(self.int()):
            self.string()
        for pc, ins in enumerate(code):
            op = ins & 0x3F
            if op in (GETGLOBAL, SETGLOBAL):
                name = constants[ins >> 14]
                out["globals"].append((op == SETGLOBAL, name, lines[pc] if pc < len(lines) else line_defined))
        # peak of locals alive at once (WoW's cap is 200 per function)
        peak = 0
        for pc in range(len(code) + 1):
            alive = sum(1 for _, start, end in locvars if start <= pc < end)
            peak = max(peak, alive)
        out["functions"].append({"line": line_defined, "upvalues": nups, "locals": peak, "main": depth == 0})
        return None


def files():
    found = sorted(glob.glob(os.path.join(ROOT, "*.lua"))) + sorted(glob.glob(os.path.join(ROOT, "Locales", "*.lua")))
    return [p for p in found if os.path.isfile(p)]


def main():
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    compile_ = lua.eval(b"function(p) local f, e = loadfile(p) if not f then return nil, e end return string.dump(f), false end")
    errors, reads, writes, headroom = [], {}, [], []
    for path in files():
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        dumped, err = compile_(path.encode("utf-8"))
        if dumped is None:
            errors.append("%s: %s" % (rel, err.decode("utf-8", "replace") if isinstance(err, bytes) else err))
            continue
        reader = Reader(dumped)
        reader.header()
        out = {"globals": [], "functions": []}
        reader.function(out)
        for is_write, name, line in out["globals"]:
            if is_write:
                if not (name in ALLOWED_WRITES or name.startswith(ALLOWED_WRITES_PREFIXES)):
                    writes.append("%s:%d: writes global %s" % (rel, line, name))
            else:
                reads.setdefault(name, []).append("%s:%d" % (rel, line))
        top = max(out["functions"], key=lambda f: f["upvalues"])
        main_locals = next(f["locals"] for f in out["functions"] if f["main"])
        most_locals = max(out["functions"], key=lambda f: f["locals"])
        headroom.append((rel, main_locals, most_locals, top))
    for e in errors:
        print("LUA 5.1 ERROR", e)
    for w in writes:
        print("GLOBAL WRITE", w)
    known = set()
    if os.path.exists(BASELINE):
        known = {line.strip() for line in open(BASELINE, encoding="utf-8") if line.strip()}
    new = sorted(name for name in reads if name not in known)
    if UPDATE:
        with open(BASELINE, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(sorted(reads)) + "\n")
        print("baseline: %d global names written to %s" % (len(reads), BASELINE))
    else:
        for name in new:
            print("NEW GLOBAL READ %s at %s" % (name, ", ".join(reads[name][:4])))
    tight = [(rel, m, ml, top) for rel, m, ml, top in headroom if m > 170 or ml["locals"] > 170 or top["upvalues"] > 50]
    for rel, main_locals, most_locals, top in headroom:
        if "Locales/" in rel:
            continue
        flag = "  <-- close to a limit" if (rel, main_locals, most_locals, top) in tight else ""
        print("%-16s main chunk %3d locals | most upvalues %2d (function at line %d)%s"
              % (rel, main_locals, top["upvalues"], top["line"], flag))
    problems = len(errors) + len(writes) + (0 if UPDATE else len(new))
    print("lua 5.1 lint: %d files, %d errors, %d global writes, %d new global reads"
          % (len(files()), len(errors), len(writes), 0 if UPDATE else len(new)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
