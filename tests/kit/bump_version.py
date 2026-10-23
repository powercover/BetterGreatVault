"""Bumps the addon's version in its three places: python bump_version.py <old> <new>"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from edits import edit  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
old, new = sys.argv[1], sys.argv[2]
edit(ROOT, "BetterGreatVault.toc", [("## Version: " + old + "\n", "## Version: " + new + "\n")])
edit(ROOT, "Core.lua", [('BGV.VERSION = "' + old + '"', 'BGV.VERSION = "' + new + '"')])
edit(ROOT, "README.md", [("version-" + old + "-", "version-" + new + "-")])
