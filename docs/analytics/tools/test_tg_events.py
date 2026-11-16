#!/usr/bin/env python3
import os
import sys
import tempfile
import textwrap
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import macos_inventory
import tg_events


def write(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(textwrap.dedent(text))


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = self.tmp.name
        write(root, "packages/TGUIKit/Sources/ViewController.swift", """
            open class ViewController : NSObject {}
            open class GenericViewController<T> : ViewController where T: NSView {}
            open class ModalViewController : ViewController {}
            open class Window : NSWindow {}
        """)
        write(root, "packages/FooUI/Sources/FooUI/Foo.swift", """
            import TGUIKit
            // class CommentedController: ViewController {}
            let text = "class StringController: ViewController {}"
            final class FooController : GenericViewController<NSView> {
                override var defaultBarTitle: String {
                    return strings().fooTitle
                }
            }
            private final class FooModal: ModalViewController {}
            final class NotAScreen: NSObject {}
            final class DeepController: FooController {}
            public func FooSettingsController(context: Context) -> InputDataController {
                let entries: () -> Void = {
                    func nested() {}
                }
                let controller = InputDataController(dataSignal: signal, title: strings().fooSettings, identifier: "foo")
                return controller
            }
            public func FooPickerModal(context: Context) -> InputDataModalController {
                let controller = InputDataController(dataSignal: signal, title: "")
                return InputDataModalController(controller)
            }
            final class Presenter {
                init(context: Context) {
                    let a = InputDataController(dataSignal: signal, title: "")
                    let b = InputDataController(dataSignal: signal, title: "")
                    let window = Window(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
                    let alert = NSAlert()
                    let panel = NSOpenPanel()
                }
            }
        """)
        write(root, "Telegram-Mac/Base.lproj/MainMenu.xib", """
            <document><objects><window title="Telegram" customClass="AppWindow"/></objects></document>
        """)
        write(root, "Telegram-Mac/de.lproj/MainMenu.xib", """
            <document><objects><window title="Telegram" customClass="AppWindow"/></objects></document>
        """)
        write(root, "packages/FooUI/Tests/FooUITests/FooTests.swift", """
            final class SnapshotWindow: NSWindow {}
        """)
        write(root, "packages/FooUI/.build/debug/Gen.swift", """
            final class BuildController: ViewController {}
        """)
        self.items = {item["key"]: item for item in macos_inventory.scan(root)}

    def tearDown(self):
        self.tmp.cleanup()

    def test_classes_follow_inheritance(self):
        self.assertIn("class:FooUI/FooController", self.items)
        self.assertIn("class:FooUI/FooModal", self.items)
        self.assertIn("class:FooUI/DeepController", self.items)
        self.assertNotIn("class:FooUI/NotAScreen", self.items)
        self.assertEqual(self.items["class:TGUIKit/Window"]["kind"], "window")

    def test_comments_strings_tests_and_build_dirs_are_ignored(self):
        keys = " ".join(self.items)
        for name in ("CommentedController", "StringController", "SnapshotWindow", "BuildController"):
            self.assertNotIn(name, keys)

    def test_titles_are_extracted(self):
        self.assertEqual(self.items["class:FooUI/FooController"]["title_key"], "fooTitle")
        self.assertEqual(self.items["inputdata:FooUI/FooSettingsController"]["title_key"], "fooSettings")
        self.assertEqual(self.items["inputdata:FooUI/FooSettingsController"]["identifier"], "foo")

    def test_inputdata_owner_and_modal(self):
        self.assertEqual(self.items["inputdata:FooUI/FooSettingsController"]["kind"], "inputdata")
        self.assertEqual(self.items["inputdata:FooUI/FooPickerModal"]["kind"], "inputdata_modal")
        self.assertIn("inputdata:FooUI/Presenter.init#1", self.items)
        self.assertIn("inputdata:FooUI/Presenter.init#2", self.items)

    def test_xib_windows_once_per_base_file(self):
        xibs = [k for k in self.items if k.startswith("xib_window:")]
        self.assertEqual(xibs, ["xib_window:Telegram-Mac/MainMenu.xib"])
        self.assertEqual(self.items[xibs[0]]["name"], "AppWindow")

    def test_direct_windows_alerts_and_panels(self):
        self.assertIn("window_site:FooUI/Presenter.init", self.items)
        self.assertIn("system_alert:FooUI/Presenter.init", self.items)
        self.assertIn("system_panel:FooUI/Presenter.init", self.items)


class RegistryTests(unittest.TestCase):
    def registry(self, extra=""):
        tmp = tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False)
        tmp.write(textwrap.dedent("""
            schema_version: 1
            platforms: [macos]
            sections:
              chat: Chat
              settings: Settings
            actions:
              show: Shown
              send: Sent
            glossary:
              folder:
                meaning: A folder
                avoid: [filter]
            params:
              peer_type:
                type: enum
                values: [user, group]
            screens:
              chat: {}
              settings.privacy: {}
            events:
              chat.message.send:
                params:
                  peer_type:
        """) + extra)
        tmp.close()
        self.addCleanup(os.unlink, tmp.name)
        return tg_events.Registry(tmp.name)

    def test_valid_registry_passes(self):
        reg = self.registry()
        self.assertTrue(reg.lint(), reg.errors)

    def test_flow_timing_resolution_is_bounded_and_generated(self):
        reg = self.registry()
        reg.raw["flows"] = {"chat.compose": {"steps": ["prepare"], "timing_resolution_ms": 1000}}
        self.assertTrue(reg.lint(), reg.errors)
        self.assertEqual(reg.resolved()["flows"]["chat.compose"]["timing_resolution_ms"], 1000)
        self.assertIn('"chat.compose": 1000', tg_events.gen_swift(reg))
        for invalid in [0, -1, 60001, 1.5, True, "1000", None]:
            reg.errors = []
            reg.raw["flows"]["chat.compose"]["timing_resolution_ms"] = invalid
            self.assertFalse(reg.lint())
            self.assertIn("timing_resolution_ms", "\n".join(reg.errors))

    def test_bad_names_fail(self):
        reg = self.registry("  sidebar.filter.click: {}\n  chat.Message.send: {}\n  chat.message.sent: {}\n")
        self.assertFalse(reg.lint())
        text = "\n".join(reg.errors)
        self.assertIn("UI widget", text)
        self.assertIn("glossary term", text)
        self.assertIn("lowercase", text)
        self.assertIn("not in `actions`", text)

    def test_glossary_term_may_contain_banned_word(self):
        reg = self.registry()
        reg.raw["glossary"]["inline_button"] = {"meaning": "A message button"}
        reg.raw["screens"]["chat.inline_button"] = {}
        self.assertTrue(reg.lint(), reg.errors)
        reg = self.registry()
        reg.raw["screens"]["chat.button"] = {}
        self.assertFalse(reg.lint())

    def test_screen_ending_with_action_fails(self):
        reg = self.registry()
        reg.raw["screens"]["settings.send"] = {}
        self.assertFalse(reg.lint())

    def test_unquoted_numeric_values_fail(self):
        reg = self.registry()
        reg.raw["params"]["count"] = {"type": "bucket", "values": [1, "2_5"]}
        self.assertFalse(reg.lint())

    def test_flow_params_cannot_override_envelope_or_common_fields(self):
        for key in ["flow", "session_id"]:
            reg = self.registry()
            reg.raw["common_params"] = {"session_id": {"type": "string"}}
            reg.raw["actions"]["end"] = "Ended"
            reg.raw["sections"]["flow"] = "Flows"
            reg.raw["events"]["flow.end"] = {"params": {"flow": {"type": "flow_id"}}}
            reg.raw["flows"] = {"chat.compose": {"steps": ["prepare"], "params": {key: {"type": "bool"}}}}
            self.assertFalse(reg.lint())
            self.assertIn("collides", "\n".join(reg.errors))

    def test_flow_outcome_conditions_are_resolved_and_validated(self):
        reg = self.registry()
        reg.raw["flow_outcomes"] = {"success": "Done", "abandoned": "Closed"}
        param = {"type": "enum", "values": ["public", "private"], "outcomes": ["success"]}
        reg.raw["flows"] = {"chat.compose": {"steps": ["prepare"], "params": {"result": param}}}
        self.assertTrue(reg.lint(), reg.errors)
        self.assertEqual(reg.resolved()["flows"]["chat.compose"]["params"]["result"]["outcomes"], ["success"])
        for invalid in [[], ["unknown"], "success", [["success"]]]:
            param["outcomes"] = invalid
            reg.errors = []
            self.assertFalse(reg.lint())
            self.assertIn("registered flow outcomes", "\n".join(reg.errors))

    def test_swift_validation_generation_preserves_constraints(self):
        reg = self.registry()
        reg.raw["platforms"].append("ios")
        reg.raw["events"]["chat.hidden.send"] = {"platforms": ["ios"], "params": {}}
        reg.raw["screens"]["chat.hidden"] = {"platforms": ["ios"]}
        reg.raw["flow_outcomes"] = {"success": "Done"}
        reg.raw["flows"] = {"chat.compose": {"steps": ["prepare"], "params": {"peer_type": {"values": ["group"]}, "result": {"type": "bool", "outcomes": ["success"], "required": True}}}}
        self.assertTrue(reg.lint(), reg.errors)
        lines = []
        tg_events.gen_swift_validation(lines, reg.resolved())
        generated = "\n".join(lines)
        self.assertNotIn("chatHidden", generated)
        self.assertNotIn('"chat.hidden"', generated)
        self.assertIn('"peer_type": .values(["group"])', generated)
        self.assertIn('"chat.compose": ["result"]', generated)
        self.assertIn('"chat.compose": ["result": ["success"]]', generated)
        self.assertIn('static let menuItems: [String: Set<String>] = [:]', generated)

    def test_checked_in_registry_reproduces_generated_validation(self):
        reg = tg_events.Registry(tg_events.DEFAULT_REGISTRY)
        self.assertTrue(reg.lint(), reg.errors)
        path = os.path.join(HERE, "..", "..", "..", "packages", "AppAnalytics", "Sources", "AppAnalytics", "AnalyticsRegistry.swift")
        with open(path, encoding="utf-8") as source:
            self.assertEqual(source.read(), tg_events.gen_swift(reg))


class TagInheritanceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = self.tmp.name
        write(self.repo, "A/Base.swift", "class Base: ViewController { func tag() { analyticsScreen = .chat; analyticsScreen = .settingsPrivacy } }")
        write(self.repo, "A/Child.swift", "class Child: Base {}")
        self.inventory = [
            {"key": "class:A/Base", "name": "Base", "base": "ViewController", "module": "A", "path": "A/Base.swift", "line": 1},
            {"key": "class:A/Child", "name": "Child", "base": "Base", "module": "A", "path": "A/Child.swift", "line": 1},
        ]
        self.mapping = {"items": {
            "class:A/Base": ["chat", "settings.privacy"],
            "class:A/Child": {"screens": ["chat", "settings.privacy"], "tags_from": "class:A/Base"},
        }}

    def errors(self):
        return tg_events.check_tags(self.inventory, self.mapping, self.repo)

    def test_declared_inheritance_uses_real_base_tags(self):
        self.assertEqual(self.errors(), [])
        del self.mapping["items"]["class:A/Child"]["tags_from"]
        self.assertEqual(len(self.errors()), 2)

    def test_missing_or_unrelated_sources_are_rejected(self):
        self.mapping["items"]["class:A/Child"]["tags_from"] = "class:A/Missing"
        self.assertTrue(any("inventoried base" in error for error in self.errors()))
        self.mapping["items"]["class:A/Child"]["tags_from"] = "class:A/Base"
        self.inventory[1]["base"] = "DifferentBase"
        self.assertTrue(any("declared base" in error for error in self.errors()))

    def test_child_cannot_claim_screens_unmapped_on_parent(self):
        self.mapping["items"]["class:A/Base"] = ["chat"]
        self.assertTrue(any("must also be mapped" in error for error in self.errors()))

    def test_comments_and_strings_do_not_count_as_tags(self):
        write(self.repo, "A/Base.swift", '''
            class Base: ViewController {
                // analyticsScreen = .chat
                /* analyticsScreen = .settingsPrivacy */
                let example = "analyticsScreen = .chat; analyticsScreen = .settingsPrivacy"
            }
        ''')
        self.assertEqual(len(self.errors()), 4)

    def test_ambiguous_cross_module_parent_is_rejected(self):
        self.inventory[0]["module"] = "B"
        self.inventory.append(dict(self.inventory[0], key="class:C/Base", module="C"))
        self.assertTrue(any("unambiguous declared base" in error for error in self.errors()))

    def test_same_module_base_wins_over_unrelated_duplicate(self):
        self.inventory.append(dict(self.inventory[0], key="class:C/Base", module="C"))
        self.assertEqual(self.errors(), [])

    def test_cyclic_mapping_is_rejected(self):
        self.inventory[0]["base"] = "Child"
        self.mapping["items"]["class:A/Base"] = {"screens": ["chat", "settings.privacy"], "tags_from": "class:A/Child"}
        self.assertTrue(any("cyclic" in error for error in self.errors()))

    def test_missing_parent_tag_is_not_hidden_by_mapping(self):
        write(self.repo, "A/Base.swift", "class Base: ViewController { func tag() { analyticsScreen = .chat } }")
        self.assertEqual(len(self.errors()), 2)
        self.assertTrue(all("settings.privacy" in error for error in self.errors()))


class CoverageTests(unittest.TestCase):
    def setUp(self):
        self.reg = RegistryTests.registry(RegistryTests())
        self.inventory = [
            {"key": "class:A/ChatController", "path": "A/Chat.swift", "line": 1},
            {"key": "class:A/BaseController", "path": "A/Base.swift", "line": 1},
        ]
        self.mapping = {
            "ignore_reasons": {"base": "Base class"},
            "items": {
                "class:A/ChatController": "chat",
                "class:A/BaseController": {"ignore": "base"},
            },
        }

    def test_complete_mapping_passes(self):
        errors, used, unused = tg_events.check_coverage(self.reg, self.inventory, self.mapping)
        self.assertEqual(errors, [])
        self.assertEqual(list(used), ["chat"])
        self.assertEqual(unused, ["settings.privacy"])

    def test_unmapped_stale_and_unknown_are_errors(self):
        self.mapping["items"].pop("class:A/BaseController")
        self.mapping["items"]["class:A/Gone"] = "chat"
        self.mapping["items"]["class:A/ChatController"] = ["chat", "chat.missing"]
        errors, _, _ = tg_events.check_coverage(self.reg, self.inventory, self.mapping)
        text = "\n".join(errors)
        self.assertIn("unmapped: class:A/BaseController", text)
        self.assertIn("stale: class:A/Gone", text)
        self.assertIn("'chat.missing' is not defined", text)

    def test_unknown_ignore_reason_is_an_error(self):
        self.mapping["items"]["class:A/BaseController"] = {"ignore": "lazy"}
        errors, _, _ = tg_events.check_coverage(self.reg, self.inventory, self.mapping)
        self.assertTrue(any("unknown ignore reason" in e for e in errors))


if __name__ == "__main__":
    unittest.main()
