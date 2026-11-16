#!/usr/bin/env python3
"""Inventory of every screen-like UI unit in the macOS app.

Usage:
  macos_inventory.py [--repo ROOT] [--json OUT]

Finds:
  class      every class that inherits, directly or not, from a view controller or window base
  inputdata  every InputDataController built in a function; wrapped in InputDataModalController => modal
  window_site, system_alert, system_panel  windows, NSAlerts and file panels created directly
  xib_window  windows defined in Interface Builder files (Base.lproj or unlocalized only)
"""

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
SCAN_DIRS = ["packages", "Telegram-Mac", "TelegramShare"]
SKIP_DIRS = {".build", ".swiftpm", "Pods"}

ROOTS = {
    "ViewController": "controller",
    "NSViewController": "controller",
    "NSWindow": "window",
    "NSPanel": "window",
    "NSWindowController": "window",
}

CLASS_DECL = re.compile(
    r"(?:(?:public|open|final|private|fileprivate|internal)\s+)*"
    r"\bclass\s+([A-Za-z_][A-Za-z0-9_]*)\s*(<[^{]*?>)?\s*:\s*([A-Za-z_][A-Za-z0-9_.]*)"
)
TYPE_DECL = re.compile(r"\b(?:class|struct|enum|extension|protocol)\s+([A-Za-z_][A-Za-z0-9_.]*)")
FUNC_DECL = re.compile(r"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)|(?<![.\w])(init)[?!]?\s*[(<]")
INPUTDATA_CALL = re.compile(r"\b(InputDataController|InputDataModalController)\s*\(")
TITLE_ARG = re.compile(r"title\s*:\s*strings\(\)\.([A-Za-z0-9_]+)")
BAR_TITLE = re.compile(r"defaultBarTitle\s*:\s*String\s*\{[^}]*?strings\(\)\.([A-Za-z0-9_]+)", re.S)
SITE_PATTERNS = [
    ("window_site", re.compile(r"(?<![A-Za-z0-9_.])(?:NS)?Window\s*\(\s*contentRect")),
    ("system_alert", re.compile(r"\bNSAlert\s*\(\s*\)")),
    ("system_panel", re.compile(r"\b(?:NSOpenPanel|NSSavePanel)\s*\(\s*\)|\bIKPictureTaker\b\s*\.\s*pictureTaker")),
]
IDENTIFIER_ARG = re.compile(r"identifier\s*:\s*\"([^\"]*)\"")


def swift_files(repo):
    for top in SCAN_DIRS:
        base = os.path.join(repo, top)
        for root, dirs, files in os.walk(base):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.endswith("Tests") and d != "Tests")
            for name in sorted(files):
                if name.endswith(".swift"):
                    yield os.path.join(root, name)


def xib_files(repo):
    for top in SCAN_DIRS:
        base = os.path.join(repo, top)
        for root, dirs, files in os.walk(base):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.endswith("Tests") and d != "Tests")
            lproj = os.path.basename(root)
            if lproj.endswith(".lproj") and lproj != "Base.lproj":
                continue
            for name in sorted(files):
                if name.endswith((".xib", ".storyboard")):
                    yield os.path.join(root, name)


XIB_WINDOW = re.compile(r"<window\b[^>]*")
XIB_CLASS = re.compile(r'customClass="([^"]+)"')


def module_of(rel):
    parts = rel.split(os.sep)
    if parts[0] == "packages" and len(parts) > 1:
        return parts[1]
    return parts[0]


def scrub(text):
    """Return (code, nostrings): comments blanked in both; string contents also blanked in nostrings."""
    code = list(text)
    bare = list(text)
    i, n = 0, len(text)

    def blank(arr, a, b):
        for k in range(a, b):
            if arr[k] != "\n":
                arr[k] = " "

    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j == -1 else j
            blank(code, i, j)
            blank(bare, i, j)
            i = j
        elif text.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if text.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif text.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            blank(code, i, j)
            blank(bare, i, j)
            i = j
        elif text.startswith('"""', i):
            j = text.find('"""', i + 3)
            j = n if j == -1 else j + 3
            blank(bare, i + 3, max(i + 3, j - 3))
            i = j
        elif c == '"':
            j = i + 1
            depth = 0
            while j < n:
                if text[j] == "\\" and j + 1 < n and text[j + 1] == "(":
                    depth += 1
                    j += 2
                    continue
                if depth and text[j] == "(":
                    depth += 1
                elif depth and text[j] == ")":
                    depth -= 1
                elif text[j] == "\\":
                    j += 2
                    continue
                elif text[j] == '"' and not depth:
                    break
                elif text[j] == "\n":
                    break
                j += 1
            blank(bare, i + 1, j)
            i = j + 1
        else:
            i += 1
    return "".join(code), "".join(bare)


def body_range(bare, start):
    """Range of the {...} body that follows the declaration at `start`."""
    paren = 0
    i, n = start, len(bare)
    while i < n:
        ch = bare[i]
        if ch in "([":
            paren += 1
        elif ch in ")]":
            paren -= 1
        elif ch == "{" and paren <= 0:
            depth, j = 0, i
            while j < n:
                if bare[j] == "{":
                    depth += 1
                elif bare[j] == "}":
                    depth -= 1
                    if depth == 0:
                        return i, j
                j += 1
            return i, n
        elif ch == ";" or (ch == "\n" and paren <= 0 and bare[start:i].count("\n") > 30):
            return None
        i += 1
    return None


class SourceFile:
    def __init__(self, path, rel, text):
        self.path = path
        self.rel = rel
        self.module = module_of(rel)
        self.code, self.bare = scrub(text)
        self.types = []
        for m in TYPE_DECL.finditer(self.bare):
            r = body_range(self.bare, m.end())
            if r:
                self.types.append((r[0], r[1], m.group(1).split(".")[-1]))
        self.funcs = []
        for m in FUNC_DECL.finditer(self.bare):
            r = body_range(self.bare, m.end())
            if r:
                self.funcs.append((r[0], r[1], m.group(1) or m.group(2)))

    def line(self, offset):
        return self.bare.count("\n", 0, offset) + 1

    def owner(self, offset):
        types = [t for t in self.types if t[0] < offset < t[1]]
        funcs = [f for f in self.funcs if f[0] < offset < f[1]]
        type_name = min(types, key=lambda t: t[1] - t[0])[2] if types else None
        if type_name:
            type_start = min(types, key=lambda t: t[1] - t[0])[0]
            funcs = [f for f in funcs if f[0] > type_start]
        func_name = max(funcs, key=lambda f: f[1] - f[0])[2] if funcs else None
        if type_name and func_name:
            return f"{type_name}.{func_name}"
        return func_name or type_name or "<top>"


def load(repo):
    files = []
    seen = set()
    for path in swift_files(repo):
        if os.path.islink(path):
            continue
        real = os.path.realpath(path)
        if real in seen:
            continue
        seen.add(real)
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
        files.append(SourceFile(path, os.path.relpath(path, repo), text))
    return files


def call_text(source, start):
    depth = 0
    bare = source.bare
    for i in range(start, min(len(bare), start + 4000)):
        if bare[i] == "(":
            depth += 1
        elif bare[i] == ")":
            depth -= 1
            if depth == 0:
                return source.code[start:i]
    return source.code[start:start + 4000]


def scan(repo):
    files = load(repo)
    classes = {}
    for source in files:
        for m in CLASS_DECL.finditer(source.bare):
            name, base = m.group(1), m.group(3).split(".")[-1]
            r = body_range(source.bare, m.end())
            classes.setdefault(name, []).append({
                "base": base,
                "source": source,
                "line": source.line(m.start()),
                "body": r,
            })

    cache = {}

    def kind_of(name, seen=()):
        if name in ROOTS:
            return ROOTS[name]
        if name in cache:
            return cache[name]
        if name in seen or name not in classes:
            return None
        result = None
        for decl in classes[name]:
            result = kind_of(decl["base"], seen + (name,))
            if result:
                break
        cache[name] = result
        return result

    items = []
    for name, decls in classes.items():
        kind = kind_of(name)
        if not kind:
            continue
        for decl in decls:
            source = decl["source"]
            title = None
            if decl["body"]:
                t = BAR_TITLE.search(source.code, decl["body"][0], decl["body"][1])
                if t:
                    title = t.group(1)
            items.append({
                "key": f"class:{source.module}/{name}",
                "kind": kind,
                "name": name,
                "base": decl["base"],
                "module": source.module,
                "path": source.rel,
                "line": decl["line"],
                "title_key": title,
            })

    for source in files:
        per_owner = {}
        for m in INPUTDATA_CALL.finditer(source.bare):
            per_owner.setdefault(source.owner(m.start()), []).append(m)
        for owner, matches in per_owner.items():
            controllers = [m for m in matches if m.group(1) == "InputDataController"]
            modal = any(m.group(1) == "InputDataModalController" for m in matches)
            if not controllers:
                continue
            for index, m in enumerate(controllers):
                call = call_text(source, m.start())
                t = TITLE_ARG.search(call)
                ident = IDENTIFIER_ARG.search(call)
                key = f"inputdata:{source.module}/{owner}"
                if len(controllers) > 1:
                    key += f"#{index + 1}"
                items.append({
                    "key": key,
                    "kind": "inputdata_modal" if modal else "inputdata",
                    "name": owner,
                    "module": source.module,
                    "path": source.rel,
                    "line": source.line(m.start()),
                    "title_key": t.group(1) if t else None,
                    "identifier": ident.group(1) if ident and ident.group(1) else None,
                })

    for source in files:
        for kind, pattern in SITE_PATTERNS:
            per_owner = {}
            for m in pattern.finditer(source.bare):
                per_owner.setdefault(source.owner(m.start()), []).append(m)
            for owner, matches in per_owner.items():
                for index, m in enumerate(matches):
                    key = f"{kind}:{source.module}/{owner}"
                    if len(matches) > 1:
                        key += f"#{index + 1}"
                    items.append({
                        "key": key,
                        "kind": kind,
                        "name": owner,
                        "module": source.module,
                        "path": source.rel,
                        "line": source.line(m.start()),
                    })

    for path in xib_files(repo):
        rel = os.path.relpath(path, repo)
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
        windows = list(XIB_WINDOW.finditer(text))
        for index, m in enumerate(windows):
            cls = XIB_CLASS.search(m.group(0))
            key = f"xib_window:{module_of(rel)}/{os.path.basename(path)}"
            if len(windows) > 1:
                key += f"#{index + 1}"
            items.append({
                "key": key,
                "kind": "xib_window",
                "name": cls.group(1) if cls else "NSWindow",
                "module": module_of(rel),
                "path": rel,
                "line": text.count("\n", 0, m.start()) + 1,
            })

    groups = {}
    for item in items:
        groups.setdefault(item["key"], []).append(item)
    for key, group in groups.items():
        if len(group) > 1:
            for item in group:
                item["key"] = f"{key}@{os.path.basename(item['path'])}"
    keys = [i["key"] for i in items]
    dupes = sorted({k for k in keys if keys.count(k) > 1})
    if dupes:
        sys.exit(f"inventory: duplicate keys {dupes}")
    items.sort(key=lambda i: i["key"])
    return items


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=DEFAULT_REPO)
    parser.add_argument("--json")
    args = parser.parse_args()
    items = scan(args.repo)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(items, f, indent=1)
    counts = {}
    for item in items:
        counts[item["kind"]] = counts.get(item["kind"], 0) + 1
    print(f"{len(items)} items: " + ", ".join(f"{v} {k}" for k, v in sorted(counts.items())))


if __name__ == "__main__":
    main()
