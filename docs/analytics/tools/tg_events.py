#!/usr/bin/env python3
"""tg-events: lint and code generation for the Telegram app events registry.

Usage:
  tg_events.py lint [--registry events.yaml]
  tg_events.py gen  [--registry events.yaml] [--json OUT] [--swift OUT]
  tg_events.py coverage [--registry events.yaml] [--mapping coverage/macos.yaml] [--repo ROOT] [--report OUT]

Requires PyYAML (pip install pyyaml).
"""

import argparse
import json
import os
import re
import sys

try:
    import yaml
except ImportError:
    sys.exit("tg-events needs PyYAML: pip install pyyaml")

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_REGISTRY = os.path.normpath(os.path.join(HERE, "..", "events.yaml"))
DEFAULT_JSON = os.path.normpath(os.path.join(HERE, "..", "generated", "events.json"))
DEFAULT_MAPPING = os.path.normpath(os.path.join(HERE, "..", "coverage", "macos.yaml"))
DEFAULT_REPORT = os.path.normpath(os.path.join(HERE, "..", "coverage", "macos.md"))

TOP_LEVEL_KEYS = {
    "schema_version", "platforms", "sections", "actions", "glossary", "common_params",
    "params", "screens", "menus", "flow_outcomes", "flows", "settings", "events", "legacy",
}
VALUE_TYPES = {"enum", "bucket"}
SCALAR_TYPES = {"bool", "int", "ms"}
REFERENCE_TYPES = {"screen_id", "menu_id", "menu_item", "setting_id", "setting_value", "flow_id", "flow_outcome", "step_list"}
COMMON_ONLY_TYPES = {"string"}
BANNED_WORDS = {
    "sidebar", "window", "tab_bar", "sheet", "popover", "drawer", "modal", "dialog",
    "button", "click", "right_click", "long_press", "swipe", "hover",
}
SEGMENT = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)*$")
VALUE = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)*$")
MAX_SEGMENTS = 5


class Registry:
    def __init__(self, path):
        self.path = path
        with open(path, encoding="utf-8") as f:
            self.raw = yaml.safe_load(f) or {}
        self.errors = []
        self.warnings = []

    def error(self, where, message):
        self.errors.append(f"{where}: {message}")

    def warn(self, where, message):
        self.warnings.append(f"{where}: {message}")

    def section(self, key):
        value = self.raw.get(key)
        return value if isinstance(value, dict) else {}

    @property
    def platforms(self):
        return list(self.raw.get("platforms") or [])

    def avoid_words(self):
        result = {}
        for term, spec in self.section("glossary").items():
            if isinstance(spec, dict):
                for word in spec.get("avoid") or []:
                    result[word] = term
        return result

    def resolve_param(self, name, spec, where, allow_common_types=False):
        globals_ = self.section("params")
        spec = dict(spec or {})
        declared_type = spec.get("type")
        if declared_type is None:
            if name not in globals_:
                self.error(where, f"param '{name}' has no type and no global definition in `params`")
                return {"type": "unknown"}
            base = dict(globals_[name])
            base.update({k: v for k, v in spec.items() if k != "type"})
            return self.resolve_param(name, base, where, allow_common_types)
        if declared_type in globals_ and declared_type not in VALUE_TYPES | SCALAR_TYPES | REFERENCE_TYPES:
            base = dict(globals_[declared_type])
            base.update({k: v for k, v in spec.items() if k != "type"})
            base["ref"] = declared_type
            resolved = self.resolve_param(declared_type, base, where, allow_common_types)
            resolved["ref"] = declared_type
            return resolved
        known = VALUE_TYPES | SCALAR_TYPES | REFERENCE_TYPES | (COMMON_ONLY_TYPES if allow_common_types else set())
        if declared_type not in known:
            self.error(where, f"param '{name}' has unknown type '{declared_type}'")
        if declared_type in VALUE_TYPES:
            values = spec.get("values")
            if not values:
                self.error(where, f"{declared_type} param '{name}' has no values")
            else:
                self.check_values(values, f"{where} param '{name}'")
        elif "values" in spec:
            self.error(where, f"param '{name}' of type '{declared_type}' must not list values")
        resolved = {"type": declared_type}
        for key in ("values", "description", "required", "ref", "outcomes"):
            if key in spec:
                resolved[key] = spec[key]
        if name in globals_ and "ref" not in resolved and spec.get("type") == globals_[name].get("type"):
            resolved["ref"] = name
        return resolved

    def check_values(self, values, where):
        seen = set()
        for value in values:
            if not isinstance(value, str):
                self.error(where, f"value {value!r} must be a string (quote it in YAML)")
                continue
            if not VALUE.match(value):
                self.error(where, f"value '{value}' must be lowercase snake_case")
            if value in seen:
                self.error(where, f"value '{value}' is listed twice")
            seen.add(value)

    def check_words(self, name, where):
        avoid = self.avoid_words()
        terms = [term.split("_") for term in self.section("glossary")]
        for segment in name.split("."):
            words = segment.split("_")
            covered = set()
            for term in terms:
                for i in range(len(words) - len(term) + 1):
                    if words[i:i + len(term)] == term:
                        covered.update(range(i, i + len(term)))
            for size in (1, 2):
                for i in range(len(words) - size + 1):
                    phrase = "_".join(words[i:i + size])
                    if phrase in BANNED_WORDS and not covered.issuperset(range(i, i + size)):
                        self.error(where, f"'{phrase}' describes a UI widget; name the product concept (RULES.md §3)")
                    if phrase in avoid and not covered.intersection(range(i, i + size)):
                        self.error(where, f"'{phrase}' is not the glossary term; use '{avoid[phrase]}'")

    def check_id(self, name, where, kind):
        parts = name.split(".")
        if not all(SEGMENT.match(p) for p in parts):
            self.error(where, f"{kind} '{name}' must be lowercase snake_case segments separated by dots")
            return
        if len(parts) > MAX_SEGMENTS:
            self.error(where, f"{kind} '{name}' has more than {MAX_SEGMENTS} segments")
        if parts[0] not in self.section("sections") and parts[0] not in self.platforms:
            self.error(where, f"{kind} '{name}' starts with '{parts[0]}', which is not a section or platform prefix")
        self.check_words(name, where)

    def check_platforms(self, spec, where):
        for platform in (spec or {}).get("platforms") or []:
            if platform not in self.platforms:
                self.error(where, f"unknown platform '{platform}'")

    def lint(self):
        raw = self.raw
        for key in raw:
            if key not in TOP_LEVEL_KEYS:
                self.error("registry", f"unknown top-level key '{key}'")
        if not isinstance(raw.get("schema_version"), int):
            self.error("registry", "schema_version must be an integer")

        actions = self.section("actions")
        for name in list(self.section("sections")) + list(actions):
            if not SEGMENT.match(name):
                self.error("vocabulary", f"'{name}' must be lowercase snake_case")

        for term, spec in self.section("glossary").items():
            if not isinstance(spec, dict) or "meaning" not in spec:
                self.error(f"glossary.{term}", "needs a `meaning`")

        for name, spec in self.section("common_params").items():
            self.resolve_param(name, spec, f"common_params.{name}", allow_common_types=True)
        for name, spec in self.section("params").items():
            if not SEGMENT.match(name):
                self.error(f"params.{name}", "param names must be snake_case")
            self.resolve_param(name, spec, f"params.{name}")

        for name, spec in self.section("screens").items():
            where = f"screens.{name}"
            self.check_id(name, where, "screen")
            if name.split(".")[-1] in actions:
                self.error(where, "a screen id must not end with an action")
            for param in (spec or {}).get("params") or []:
                if param not in self.section("params"):
                    self.error(where, f"param '{param}' is not defined in `params`")
            self.check_platforms(spec, where)

        for name, spec in self.section("menus").items():
            where = f"menus.{name}"
            self.check_id(name, where, "menu")
            items = (spec or {}).get("items") or []
            if not items:
                self.error(where, "menu has no items")
            self.check_values(items, where)
            for item in items:
                self.check_words(item, f"{where} item '{item}'")
            self.check_platforms(spec, where)

        outcomes = self.section("flow_outcomes")
        for outcome in outcomes:
            if not VALUE.match(outcome):
                self.error("flow_outcomes", f"'{outcome}' must be snake_case")

        for name, spec in self.section("flows").items():
            where = f"flows.{name}"
            spec = spec or {}
            self.check_id(name, where, "flow")
            resolution = spec.get("timing_resolution_ms", 1)
            if type(resolution) is not int or resolution < 1 or resolution > 60000:
                self.error(where, "timing_resolution_ms must be an integer from 1 to 60000")
            screen = spec.get("screen")
            if screen is not None and screen not in self.section("screens"):
                self.error(where, f"screen '{screen}' is not defined in `screens`")
            steps = spec.get("steps") or []
            if not steps:
                self.error(where, "flow has no steps")
            self.check_values(steps, f"{where} steps")
            for step in steps:
                self.check_words(step, f"{where} step '{step}'")
            for param, pspec in (spec.get("params") or {}).items():
                resolved = self.resolve_param(param, pspec, where)
                if not SEGMENT.match(param):
                    self.error(where, f"param '{param}' must be snake_case")
                reserved = set(self.section("common_params")) | set((self.section("events").get("flow.end") or {}).get("params") or {})
                if param in reserved:
                    self.error(where, f"param '{param}' collides with a common or flow envelope param")
                if "outcomes" in resolved:
                    allowed = resolved["outcomes"]
                    if not isinstance(allowed, list) or not allowed or any(not isinstance(value, str) or value not in outcomes for value in allowed):
                        self.error(where, f"param '{param}' outcomes must name registered flow outcomes")
            self.check_platforms(spec, where)

        for name, spec in self.section("settings").items():
            where = f"settings.{name}"
            if not isinstance(spec, dict) or not spec.get("values"):
                self.error(where, "setting needs `values`")
                continue
            if not all(SEGMENT.match(p) for p in name.split(".")):
                self.error(where, "setting ids must be lowercase snake_case segments")
            self.check_values(spec["values"], where)
            self.check_platforms(spec, where)

        for name, spec in self.section("events").items():
            where = f"events.{name}"
            spec = spec or {}
            self.check_id(name, where, "event")
            parts = name.split(".")
            if len(parts) < 2:
                self.error(where, "event names need at least 2 segments")
            if parts[-1] not in actions:
                self.error(where, f"last segment '{parts[-1]}' is not in `actions`")
            for param, pspec in (spec.get("params") or {}).items():
                if not SEGMENT.match(param):
                    self.error(where, f"param '{param}' must be snake_case")
                if param in self.section("common_params"):
                    self.error(where, f"param '{param}' is a common param and must not be redeclared")
                self.resolve_param(param, pspec, where)
            self.check_platforms(spec, where)

        legacy = self.section("legacy")
        for name in legacy:
            if name in self.section("events"):
                self.error(f"legacy.{name}", "also defined in `events`")

        return not self.errors

    def resolved(self):
        def params_map(spec):
            return {name: self.resolve_param(name, pspec, "gen") for name, pspec in ((spec or {}).get("params") or {}).items()}

        result = {
            "schema_version": self.raw.get("schema_version"),
            "platforms": self.platforms,
            "sections": self.section("sections"),
            "actions": self.section("actions"),
            "glossary": self.section("glossary"),
            "common_params": {n: self.resolve_param(n, s, "gen", allow_common_types=True) for n, s in self.section("common_params").items()},
            "params": {n: self.resolve_param(n, s, "gen") for n, s in self.section("params").items()},
            "screens": {n: {k: v for k, v in (s or {}).items()} for n, s in self.section("screens").items()},
            "menus": self.section("menus"),
            "settings": self.section("settings"),
            "flow_outcomes": self.section("flow_outcomes"),
            "flows": {},
            "events": {},
            "legacy": self.section("legacy"),
        }
        for name, spec in self.section("flows").items():
            entry = {k: v for k, v in (spec or {}).items() if k != "params"}
            entry["params"] = params_map(spec)
            result["flows"][name] = entry
        for name, spec in self.section("events").items():
            entry = {k: v for k, v in (spec or {}).items() if k != "params"}
            entry["params"] = params_map(spec)
            result["events"][name] = entry
        return result


SWIFT_KEYWORDS = {
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init",
    "inout", "internal", "let", "open", "operator", "private", "protocol", "public", "static", "struct",
    "subscript", "typealias", "var", "break", "case", "continue", "default", "defer", "do", "else",
    "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while", "as",
    "catch", "false", "is", "nil", "rethrows", "super", "self", "Self", "throw", "throws", "true", "try",
}


def camel(name):
    if name[:1].isdigit():
        return "_" + name.replace(".", "_")
    words = [w for w in re.split(r"[._]", name) if w]
    text = words[0] + "".join(w[:1].upper() + w[1:] for w in words[1:])
    if text[:1].isdigit():
        text = "_" + text
    if text in SWIFT_KEYWORDS:
        text = f"`{text}`"
    return text


def pascal(name):
    words = [w for w in re.split(r"[._]", name) if w]
    text = "".join(w[:1].upper() + w[1:] for w in words)
    if text[:1].isdigit():
        text = "_" + text
    return text


def swift_enum(lines, indent, type_name, values, conformances="String"):
    pad = "    " * indent
    lines.append(f"{pad}public enum {type_name}: {conformances} {{")
    seen = set()
    for value in values:
        case = camel(value)
        if case in seen:
            raise SystemExit(f"gen: Swift case collision for '{value}' in {type_name}")
        seen.add(case)
        lines.append(f"{pad}    case {case} = \"{value}\"")
    lines.append(f"{pad}}}")


SWIFT_SCALARS = {
    "bool": ("Bool", ".bool(v)"),
    "int": ("Int", ".number(Double(v))"),
    "ms": ("Int", ".number(Double(v))"),
}


def gen_swift(reg):
    data = reg.resolved()
    lines = [
        "// Generated by docs/analytics/tools/tg_events.py from docs/analytics/events.yaml. Do not edit.",
        "",
        "import Foundation",
        "import TelegramCore",
        "",
        "public enum AnalyticsSchema {",
        f"    public static let version = {data['schema_version']}",
        "}",
        "",
    ]
    swift_enum(lines, 0, "AnalyticsEventName", list(data["events"]))
    lines.append("")
    swift_enum(lines, 0, "AnalyticsScreen", list(data["screens"]))
    lines.append("")
    swift_enum(lines, 0, "AnalyticsMenu", list(data["menus"]))
    lines.append("")
    swift_enum(lines, 0, "AnalyticsSetting", list(data["settings"]))
    lines.append("")
    swift_enum(lines, 0, "AnalyticsFlowOutcome", list(data["flow_outcomes"]))
    lines.append("")
    lines.append("public enum AnalyticsValues {")
    for name, spec in data["params"].items():
        if spec.get("type") in VALUE_TYPES:
            swift_enum(lines, 1, pascal(name), spec["values"])
    for name, spec in data["common_params"].items():
        if spec.get("type") in VALUE_TYPES and pascal(name) not in {pascal(n) for n in data["params"]}:
            swift_enum(lines, 1, pascal(name), spec["values"])
    lines.append("}")
    lines.append("")
    lines.append("public enum AnalyticsMenuItems {")
    for name, spec in data["menus"].items():
        swift_enum(lines, 1, pascal(name), spec["items"])
    lines.append("}")
    lines.append("")
    lines.append("public protocol AnalyticsFlowSpec {")
    lines.append("    associatedtype Step: RawRepresentable where Step.RawValue == String")
    lines.append("    associatedtype Param: RawRepresentable & Hashable where Param.RawValue == String")
    lines.append("    static var id: String { get }")
    lines.append("}")
    lines.append("")
    lines.append("public enum AnalyticsFlows {")
    extensions = []
    for name, spec in data["flows"].items():
        type_name = pascal(name)
        full = f"AnalyticsFlows.{type_name}"
        lines.append(f"    public enum {type_name}: AnalyticsFlowSpec {{")
        lines.append(f"        public static let id = \"{name}\"")
        swift_enum(lines, 2, "Step", spec["steps"])
        params = spec["params"]
        if params:
            swift_enum(lines, 2, "Param", list(params), "String, Hashable")
        else:
            lines.append("        public enum Param: String, Hashable {")
            lines.append("            case none")
            lines.append("        }")
        setters = []
        for pname, pspec in params.items():
            if pspec.get("type") in VALUE_TYPES:
                if "ref" in pspec:
                    value_type = f"AnalyticsValues.{pascal(pspec['ref'])}"
                else:
                    value_type = f"{full}.{pascal(pname)}"
                    swift_enum(lines, 2, pascal(pname), pspec["values"])
                encode = ".string(v.rawValue)"
            elif pspec.get("type") in SWIFT_SCALARS:
                value_type, encode = SWIFT_SCALARS[pspec["type"]]
            else:
                continue
            label = camel(pname).strip("`")
            setters.append(f"    public func set({label} value: {value_type}?) {{")
            setters.append(f"        setValue(.{camel(pname)}, value.map {{ v in {encode} }})")
            setters.append("    }")
            setters.append(f"    public func setIfAbsent({label} v: {value_type}) {{")
            setters.append(f"        setValueIfAbsent(.{camel(pname)}, {encode})")
            setters.append("    }")
        lines.append("    }")
        if setters:
            extensions.append(f"extension AnalyticsFlow where Spec == {full} {{")
            extensions.extend(setters)
            extensions.append("}")
            extensions.append("")
    lines.append("}")
    lines.append("")
    lines.extend(extensions)
    gen_swift_settings(lines, data)
    gen_swift_events(lines, data)
    gen_swift_validation(lines, data)
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines) + "\n"


def gen_swift_validation(lines, data):
    def values(items):
        return "[" + ", ".join(json.dumps(item) for item in items) + "]"

    def supported(spec):
        return "platforms" not in spec or "macos" in spec["platforms"]

    def rule(spec):
        kind = spec["type"]
        if kind in VALUE_TYPES:
            return f".values({values(spec['values'])})"
        return "." + {
            "bool": "boolean", "int": "integer", "ms": "integer", "string": "metadata",
            "screen_id": "screen", "menu_id": "menu", "menu_item": "menuItem",
            "setting_id": "setting", "setting_value": "settingValue", "flow_id": "flow",
            "flow_outcome": "outcome", "step_list": "steps",
        }[kind]

    def params(spec):
        entries = [f"{json.dumps(key)}: {rule(value)}" for key, value in spec.items()]
        return "[" + ", ".join(entries) + "]" if entries else "[:]"

    def mapping(field, value_type, entries):
        if not entries:
            lines.append(f"    static let {field}: {value_type} = [:]")
        else:
            lines.append(f"    static let {field}: {value_type} = [")
            lines.extend(f"        {entry}," for entry in entries)
            lines.append("    ]")

    lines.append("enum AnalyticsValidationSpec {")
    mapping("events", "[AnalyticsEventName: [String: AnalyticsParameterRule]]", [f".{camel(name)}: {params(spec['params'])}" for name, spec in data["events"].items() if supported(spec)])
    lines.append(f"    static let common: [String: AnalyticsParameterRule] = {params(data['common_params'])}")
    lines.append(f"    static let screens: Set<String> = {values(name for name, spec in data['screens'].items() if supported(spec))}")
    lines.append(f"    static let outcomes: Set<String> = {values(data['flow_outcomes'])}")
    for field, source, key in [("menuItems", "menus", "items"), ("settingValues", "settings", "values"), ("flowSteps", "flows", "steps")]:
        mapping(field, "[String: Set<String>]", [f"{json.dumps(name)}: {values(spec[key])}" for name, spec in data[source].items() if supported(spec)])
    mapping("flowParams", "[String: [String: AnalyticsParameterRule]]", [f"{json.dumps(name)}: {params(spec['params'])}" for name, spec in data["flows"].items() if supported(spec)])
    mapping("flowTimingResolution", "[String: Int]", [f"{json.dumps(name)}: {spec.get('timing_resolution_ms', 1)}" for name, spec in data["flows"].items() if supported(spec)])
    required_entries = []
    outcome_entries = []
    for name, spec in data["flows"].items():
        if supported(spec):
            required = [key for key, param in spec["params"].items() if param.get("required")]
            required_entries.append(f"{json.dumps(name)}: {values(required)}")
            entries = [f"{json.dumps(key)}: {values(param['outcomes'])}" for key, param in spec["params"].items() if "outcomes" in param]
            if entries:
                outcome_entries.append(f"{json.dumps(name)}: [{', '.join(entries)}]")
    mapping("flowRequired", "[String: Set<String>]", required_entries)
    mapping("flowParamOutcomes", "[String: [String: Set<String>]]", outcome_entries)
    lines.append("}")
    lines.append("")


def bucket_bounds(value):
    m = re.fullmatch(r"under_(\d+)([a-z]*)", value)
    if m:
        return None, unit_value(m.group(1), m.group(2))
    m = re.fullmatch(r"(\d+)([a-z]*)_plus", value)
    if m:
        return unit_value(m.group(1), m.group(2)), None
    m = re.fullmatch(r"(\d+)([a-z]*)_(\d+)([a-z]*)", value)
    if m:
        return unit_value(m.group(1), m.group(2) or m.group(4)), unit_value(m.group(3), m.group(4))
    m = re.fullmatch(r"(\d+)", value)
    if m:
        return int(m.group(1)), int(m.group(1))
    raise SystemExit(f"gen: cannot read bucket bounds from '{value}'")


def unit_value(number, unit):
    scale = {"": 1, "s": 1, "m": 60, "h": 3600}
    if unit not in scale:
        raise SystemExit(f"gen: unknown bucket unit '{unit}'")
    return int(number) * scale[unit]


def swift_bucket_init(lines, indent, values):
    pad = "    " * indent
    lines.append(f"{pad}public init(bucketing value: Int) {{")
    for value in values:
        low, high = bucket_bounds(value)
        case = camel(value)
        if high is None:
            lines.append(f"{pad}    self = .{case}")
            break
        exclusive = value.startswith("under_") or re.search(r"[smh]$", value) is not None
        limit = high - 1 if exclusive else high
        lines.append(f"{pad}    if value <= {limit} {{ self = .{case}; return }}")
    else:
        lines.append(f"{pad}    self = .{camel(values[-1])}")
    lines.append(f"{pad}}}")


def swift_param_type(event, pname, pspec, nested):
    kind = pspec.get("type")
    if kind in ("enum", "bucket"):
        if pspec.get("ref") and pspec["ref"] in ("via", "peer_type", "count", "message_kind", "call_duration"):
            return f"AnalyticsValues.{pascal(pspec['ref'])}", ".string(v.rawValue)"
        nested.append((pascal(pname), pspec["values"], kind == "bucket"))
        return f"AnalyticsEvents.{pascal(event)}{pascal(pname)}", ".string(v.rawValue)"
    if kind == "screen_id":
        return "AnalyticsScreen", ".string(v.rawValue)"
    if kind == "menu_id":
        return "AnalyticsMenu", ".string(v.rawValue)"
    if kind in SWIFT_SCALARS:
        return SWIFT_SCALARS[kind]
    return None, None


SKIP_TYPED = {"flow.end", "settings.change", "menu.select"}


def gen_swift_events(lines, data):
    lines.append("public struct AnalyticsEvent {")
    lines.append("    public let name: AnalyticsEventName")
    lines.append("    public let params: [String: JSON]")
    lines.append("    public init(name: AnalyticsEventName, params: [String: JSON]) {")
    lines.append("        self.name = name")
    lines.append("        self.params = params")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    lines.append("public enum AnalyticsEventSpec {")
    lines.append("    public static let params: [AnalyticsEventName: Set<String>] = [")
    for name, spec in data["events"].items():
        keys = ", ".join(f'"{k}"' for k in spec.get("params", {}))
        lines.append(f"        .{camel(name)}: [{keys}],")
    lines.append("    ]")
    lines.append("    public static let required: [AnalyticsEventName: Set<String>] = [")
    for name, spec in data["events"].items():
        keys = [k for k, v in spec.get("params", {}).items() if v.get("required")]
        if keys:
            lines.append(f"        .{camel(name)}: [{', '.join(chr(34) + k + chr(34) for k in keys)}],")
    lines.append("    ]")
    lines.append("}")
    lines.append("")
    nested_types = []
    funcs = []
    for name, spec in data["events"].items():
        if name in SKIP_TYPED:
            continue
        nested = []
        args = []
        body = [f"        var params: [String: JSON] = [:]"]
        for pname, pspec in spec.get("params", {}).items():
            value_type, encode = swift_param_type(name, pname, pspec, nested)
            if value_type is None:
                raise SystemExit(f"gen: no Swift type for {name}.{pname} ({pspec.get('type')})")
            label = camel(pname).strip("`")
            if pspec.get("required"):
                args.append(f"{label}: {value_type}")
                body.append(f"        params[\"{pname}\"] = {{ (v: {value_type}) -> JSON in {encode} }}({label})")
            else:
                args.append(f"{label}: {value_type}? = nil")
                body.append(f"        if let v = {label} {{ params[\"{pname}\"] = {encode} }}")
        for type_suffix, values, is_bucket in nested:
            type_name = f"{pascal(name)}{type_suffix}"
            nested_types.append((type_name, values, is_bucket))
        funcs.append(f"    public static func {camel(name)}({', '.join(args)}) -> AnalyticsEvent {{")
        funcs.extend(body)
        funcs.append(f"        return AnalyticsEvent(name: .{camel(name)}, params: params)")
        funcs.append("    }")
    for menu in data["menus"]:
        funcs.append(f"    public static func menuSelect({camel(menu).strip('`')} item: AnalyticsMenuItems.{pascal(menu)}, screen: AnalyticsScreen? = nil) -> AnalyticsEvent {{")
        funcs.append(f"        var params: [String: JSON] = [\"menu\": .string(AnalyticsMenu.{camel(menu)}.rawValue), \"item\": .string(item.rawValue)]")
        funcs.append("        if let v = screen { params[\"screen\"] = .string(v.rawValue) }")
        funcs.append("        return AnalyticsEvent(name: .menuSelect, params: params)")
        funcs.append("    }")
    funcs.append("    public static func settingsChange(_ change: AnalyticsSettingChange) -> AnalyticsEvent {")
    funcs.append("        return AnalyticsEvent(name: .settingsChange, params: [\"setting\": .string(change.setting.rawValue), \"value\": .string(change.value)])")
    funcs.append("    }")
    lines.append("public enum AnalyticsEvents {")
    for type_name, values, is_bucket in nested_types:
        swift_enum(lines, 1, type_name, values)
        if is_bucket:
            lines.pop()
            swift_bucket_init(lines, 2, values)
            lines.append("    }")
    lines.extend(funcs)
    lines.append("}")
    lines.append("")
    for name, spec in data["params"].items():
        if spec.get("type") == "bucket":
            lines.append(f"extension AnalyticsValues.{pascal(name)} {{")
            swift_bucket_init(lines, 1, spec["values"])
            lines.append("}")
            lines.append("")


def gen_swift_settings(lines, data):
    lines.append("public enum AnalyticsSettingValues {")
    for name, spec in data["settings"].items():
        swift_enum(lines, 1, pascal(name), spec["values"])
    lines.append("}")
    lines.append("")
    lines.append("public enum AnalyticsSettingChange {")
    for name in data["settings"]:
        lines.append(f"    case {camel(name)}(AnalyticsSettingValues.{pascal(name)})")
    lines.append("")
    lines.append("    public var setting: AnalyticsSetting {")
    lines.append("        switch self {")
    for name in data["settings"]:
        lines.append(f"        case .{camel(name)}: return .{camel(name)}")
    lines.append("        }")
    lines.append("    }")
    lines.append("")
    lines.append("    public var value: String {")
    lines.append("        switch self {")
    for name in data["settings"]:
        lines.append(f"        case let .{camel(name)}(v): return v.rawValue")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    lines.append("")


def gen_swift_coverage(mapping):
    lines = [
        "// Generated by docs/analytics/tools/tg_events.py from docs/analytics/coverage/macos.yaml. Do not edit.",
        "",
        "import Foundation",
        "",
        "public enum AnalyticsCoverage {",
        "    public static let screenForClass: [String: AnalyticsScreen] = [",
    ]
    rows = []
    for key, value in sorted((mapping.get("items") or {}).items()):
        if not key.startswith("class:"):
            continue
        entry = mapping_entry(value)
        if "ignore" in entry or len(entry.get("screens") or []) != 1:
            continue
        class_name = key.split("/", 1)[1]
        rows.append(f'        "{class_name}": .{camel(entry["screens"][0])},')
    lines.extend(rows)
    lines.append("    ]")
    lines.append("}")
    return "\n".join(lines) + "\n"


def mapping_entry(value):
    if isinstance(value, str):
        return {"screens": [value]}
    if isinstance(value, list):
        return {"screens": list(value)}
    if isinstance(value, dict):
        entry = dict(value)
        if "screen" in entry:
            entry["screens"] = [entry.pop("screen")]
        return entry
    return {}


def check_coverage(reg, inventory, mapping):
    errors = []
    reasons = mapping.get("ignore_reasons") or {}
    items = mapping.get("items") or {}
    screens = reg.section("screens")
    inventory_keys = {item["key"] for item in inventory}
    used = {}
    for item in inventory:
        if item["key"] not in items:
            errors.append(f"unmapped: {item['key']} ({item['path']}:{item['line']})")
    for key, value in items.items():
        if key not in inventory_keys:
            errors.append(f"stale: {key} is mapped but no longer in the inventory")
            continue
        entry = mapping_entry(value)
        if "ignore" in entry:
            if entry["ignore"] not in reasons:
                errors.append(f"{key}: unknown ignore reason '{entry['ignore']}'")
            if entry.get("screens"):
                errors.append(f"{key}: cannot both ignore and map to screens")
            continue
        if not entry.get("screens"):
            errors.append(f"{key}: needs a screen, a list of screens or `ignore`")
        for screen in entry.get("screens") or []:
            if screen not in screens:
                errors.append(f"{key}: screen '{screen}' is not defined in events.yaml")
            used.setdefault(screen, []).append(key)
    unused = [s for s in screens if s not in used]
    return errors, used, unused


def check_tags(inventory, mapping, repo):
    import macos_inventory

    by_key = {item["key"]: item for item in inventory}
    items = mapping.get("items") or {}
    errors = []

    def source_keys(key, seen=()):
        if key in seen:
            errors.append(f"{key}: cyclic tags_from reference")
            return []
        entry = mapping_entry(items.get(key))
        parent_key = entry.get("tags_from")
        if parent_key is None:
            return [key]
        item = by_key[key]
        if not key.startswith("class:") or not isinstance(parent_key, str) or parent_key not in by_key:
            errors.append(f"{key}: tags_from must name an inventoried base class")
            return [key]
        candidates = [candidate for candidate in inventory if candidate["key"].startswith("class:") and candidate.get("name") == item.get("base")]
        local = [candidate for candidate in candidates if candidate.get("module") == item.get("module")]
        candidates = local or candidates
        if len(candidates) != 1 or candidates[0]["key"] != parent_key:
            errors.append(f"{key}: tags_from '{parent_key}' is not its unambiguous declared base class")
            return [key]
        parent = mapping_entry(items.get(parent_key))
        if "ignore" in parent or not set(entry.get("screens") or []).issubset(parent.get("screens") or []):
            errors.append(f"{key}: tags_from screens must also be mapped on '{parent_key}'")
            return [key]
        return [key] + source_keys(parent_key, seen + (key,))

    for key, value in items.items():
        entry = mapping_entry(value)
        if "ignore" in entry or key not in by_key:
            continue
        screens = entry.get("screens") or []
        kind = key.split(":", 1)[0]
        if kind == "class" and len(screens) == 1 and "tags_from" not in entry:
            continue
        text = ""
        paths = []
        for source_key in source_keys(key):
            relative = by_key[source_key]["path"]
            path = os.path.join(repo, relative)
            try:
                with open(path, encoding="utf-8", errors="replace") as f:
                    _, bare = macos_inventory.scrub(f.read())
                    text += "\n" + bare
                    paths.append(relative)
            except OSError:
                errors.append(f"{key}: cannot read {path}")
        for screen in screens:
            token = camel(screen).strip("`")
            patterns = [
                r"analyticsScreen\s*=\s*\.?" + re.escape(token) + r"\b",
                r"\.analytics\(\s*\." + re.escape(token) + r"\b",
                r"showStandalone\(\s*\." + re.escape(token) + r"\b",
                r"screens\.show\([^)]*screen:\s*\." + re.escape(token) + r"\b",
                r"AnalyticsScreen\." + re.escape(token) + r"\b",
            ]
            if not any(re.search(p, text) for p in patterns):
                errors.append(f"{key}: no tag for screen '{screen}' in {', '.join(paths)}")
    return errors


def coverage_report(inventory, mapping, used, unused):
    items = mapping.get("items") or {}
    by_key = {item["key"]: item for item in inventory}
    lines = [
        f"# {mapping.get('platform', 'macos')} screen coverage",
        "",
        "Generated by `tools/tg_events.py coverage`. Do not edit.",
        "",
        f"- Inventory items: {len(inventory)}",
        f"- Mapped to screens: {sum(1 for v in items.values() if 'ignore' not in mapping_entry(v))}",
        f"- Ignored with a reason: {sum(1 for v in items.values() if 'ignore' in mapping_entry(v))}",
        f"- Registry screens used: {len(used)}",
        f"- Registry screens with no source on this platform: {len(unused)}",
        "",
        "## Screens",
        "",
        "| Screen | Sources |",
        "|---|---|",
    ]
    for screen in sorted(used):
        sources = ", ".join(f"`{by_key[k]['path'].split('/')[-1]}:{by_key[k]['line']}` {k.split('/', 1)[-1]}" for k in used[screen])
        lines.append(f"| `{screen}` | {sources} |")
    lines += ["", "## Ignored", "", "| Item | Reason | Note |", "|---|---|---|"]
    for key in sorted(items):
        entry = mapping_entry(items[key])
        if "ignore" in entry:
            lines.append(f"| `{key}` | {entry['ignore']} | {entry.get('note', '')} |")
    if unused:
        lines += ["", "## Registry screens with no source on this platform", ""]
        lines += [f"- `{s}`" for s in unused]
    return "\n".join(lines) + "\n"


def write(path, content):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"wrote {path}")


def main():
    parser = argparse.ArgumentParser(prog="tg-events")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("lint", "gen", "coverage"):
        cmd = sub.add_parser(name)
        cmd.add_argument("--registry", default=DEFAULT_REGISTRY)
        if name == "gen":
            cmd.add_argument("--json", default=DEFAULT_JSON, help="resolved registry for any language")
            cmd.add_argument("--swift", help="Swift registry for the macOS AppAnalytics runtime")
            cmd.add_argument("--swift-coverage", help="Swift class-to-screen table from the coverage mapping")
            cmd.add_argument("--mapping", default=DEFAULT_MAPPING)
            cmd.add_argument("--check", action="store_true", help="fail if a generated file is missing or out of date instead of writing it")
        if name == "coverage":
            cmd.add_argument("--mapping", default=DEFAULT_MAPPING)
            cmd.add_argument("--repo", default=os.path.normpath(os.path.join(HERE, "..", "..", "..")))
            cmd.add_argument("--report", default=DEFAULT_REPORT)
            cmd.add_argument("--tags", action="store_true", help="also check that every mode, factory and standalone screen is tagged in code")
    args = parser.parse_args()

    reg = Registry(args.registry)
    ok = reg.lint()
    for warning in reg.warnings:
        print(f"warning: {warning}")
    for error in reg.errors:
        print(f"error: {error}")
    if not ok:
        sys.exit(f"{len(reg.errors)} error(s)")
    counts = {k: len(reg.section(k)) for k in ("events", "screens", "menus", "flows", "settings")}
    print("lint ok: " + ", ".join(f"{v} {k}" for k, v in counts.items()))

    if args.command == "coverage":
        sys.path.insert(0, HERE)
        import macos_inventory
        inventory = macos_inventory.scan(args.repo)
        with open(args.mapping, encoding="utf-8") as f:
            mapping = yaml.safe_load(f) or {}
        errors, used, unused = check_coverage(reg, inventory, mapping)
        if args.tags:
            errors += check_tags(inventory, mapping, args.repo)
        for error in errors:
            print(f"error: {error}")
        if errors:
            sys.exit(f"coverage: {len(errors)} error(s)")
        if args.report:
            write(args.report, coverage_report(inventory, mapping, used, unused))
        print(f"coverage ok: {len(inventory)} items decided, {len(used)} screens used, {len(unused)} registry screens without a macOS source")

    if args.command == "gen":
        outputs = [(args.json, json.dumps(reg.resolved(), indent=2, ensure_ascii=False) + "\n")]
        if args.swift:
            outputs.append((args.swift, gen_swift(reg)))
        if args.swift_coverage:
            with open(args.mapping, encoding="utf-8") as f:
                outputs.append((args.swift_coverage, gen_swift_coverage(yaml.safe_load(f) or {})))
        if args.check:
            stale = []
            for path, content in outputs:
                try:
                    with open(path, encoding="utf-8") as f:
                        current = f.read()
                except OSError:
                    current = None
                if current != content:
                    stale.append(path)
            for path in stale:
                print(f"error: {path} is out of date; run tg_events.py gen")
            if stale:
                sys.exit(f"gen --check: {len(stale)} stale file(s)")
            print("generated files are up to date")
        else:
            for path, content in outputs:
                write(path, content)


if __name__ == "__main__":
    main()
