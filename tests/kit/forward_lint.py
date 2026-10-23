# Flags uses of a file-level `local function NAME` / `local NAME =` before the line that defines
# it (in Lua that use resolves to a global, usually nil), unless NAME was forward-declared.
import re, sys, glob, os
root = os.environ.get("BGV_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
problems = 0
for path in sorted(glob.glob(os.path.join(root, "*.lua"))):
    lines = open(path, encoding="utf-8").read().split("\n")
    defined = {}
    forward = set()
    for number, line in enumerate(lines, 1):
        m = re.match(r"^local function ([A-Za-z_][A-Za-z0-9_]*)", line)
        if m and m.group(1) not in defined:
            defined[m.group(1)] = number
        m = re.match(r"^local ([A-Za-z_][A-Za-z0-9_]*)\s*$", line)
        if m:
            forward.add(m.group(1))
            defined.setdefault(m.group(1), number)
        m = re.match(r"^local ([A-Za-z_][A-Za-z0-9_]*)\s*=", line)
        if m and m.group(1) not in defined:
            defined[m.group(1)] = number
    for number, line in enumerate(lines, 1):
        code = line.split("--", 1)[0]
        for name, where in defined.items():
            if number < where and name not in forward:
                if re.search(r"(?<![\w.:])" + re.escape(name) + r"\s*\(", code):
                    print(f"{os.path.basename(path)}:{number}: {name}() used before its definition at line {where}")
                    problems += 1
print("forward lint:", "clean" if problems == 0 else f"{problems} problem(s)")
