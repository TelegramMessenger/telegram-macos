import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
MTPROTO_PROJECT = Path("core-xprojects/mtproto-engine/MTProtoEngine.xcodeproj/project.pbxproj")


def write(path, contents, executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents)
    if executable:
        path.chmod(0o755)
    return path


class TemporaryTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="telegram build setup ")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.environment = dict(os.environ, PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}")

    def run_script(self, name, *arguments):
        return subprocess.run(
            ["bash", str(self.root / "scripts" / name), *arguments],
            env=self.environment,
            capture_output=True,
            text=True,
        )

    def copy_script(self, name):
        destination = self.root / "scripts" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "scripts" / name, destination)


class SetupTests(TemporaryTest):
    def setUp(self):
        super().setUp()
        self.copy_script("setup_build_env.sh")
        self.command_log = self.root / "commands"
        self.environment["BUILD_SETUP_COMMAND_LOG"] = str(self.command_log)
        write(
            self.bin / "uname",
            '#!/bin/sh\ncase "$1" in -s) echo Darwin;; -m) echo x86_64;; *) exit 1;; esac\n',
            executable=True,
        )
        write(
            self.bin / "brew",
            '#!/bin/sh\nprintf "brew %s\\n" "$*" >> "$BUILD_SETUP_COMMAND_LOG"\n'
            'if [ "$1" = "--version" ]; then echo "Homebrew fixture"; fi\n',
            executable=True,
        )
        write(
            self.bin / "git",
            '#!/bin/sh\nprintf "git %s\\n" "$*" >> "$BUILD_SETUP_COMMAND_LOG"\n'
            'exit "${BUILD_SETUP_GIT_EXIT_CODE:-0}"\n',
            executable=True,
        )
        write(
            self.bin / "xcode-select",
            '#!/bin/sh\necho /Applications/Xcode.app/Contents/Developer\n',
            executable=True,
        )
        write(self.bin / "xcodebuild", '#!/bin/sh\necho "Xcode fixture"\n', executable=True)
        write(
            self.root / "scripts/configure_frameworks.sh",
            '#!/bin/sh\nprintf "frameworks\\n" >> "$BUILD_SETUP_COMMAND_LOG"\n',
        )

    def test_preparation_installs_build_tools_without_homebrew_openssl(self):
        result = self.run_script("setup_build_env.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        commands = self.command_log.read_text().splitlines()
        installs = [line.split()[2:] for line in commands if line.startswith("brew install ")]
        self.assertEqual(len(installs), 1)
        self.assertTrue({"cmake", "ninja", "meson", "nasm", "yasm"}.issubset(installs[0]))
        self.assertFalse(any(package.startswith("openssl") for package in installs[0]))
        self.assertIn("submodule update --init --recursive", "\n".join(commands))
        self.assertIn("Environment ready.", result.stdout)

    def test_failed_submodules_stop_before_success_or_framework_build(self):
        self.environment["BUILD_SETUP_GIT_EXIT_CODE"] = "37"
        result = self.run_script("setup_build_env.sh", "--build")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Submodule initialization failed", result.stderr)
        self.assertNotIn("Environment ready.", result.stdout)
        self.assertNotIn("frameworks", self.command_log.read_text().splitlines())


class Xcode27Tests(TemporaryTest):
    def setUp(self):
        super().setUp()
        self.copy_script("xcode27.sh")
        source = (ROOT / "scripts/xcode27.sh").read_text()
        project_paths = set(re.findall(r"^\s+(\S+\.xcodeproj/project\.pbxproj)$", source, re.MULTILINE))
        project_paths.add(str(MTPROTO_PROJECT))
        self.sources = []
        for name in sorted(project_paths):
            path = Path(name)
            if (ROOT / path).is_file():
                contents = (ROOT / path).read_text()
            else:
                contents = (
                    "\t\t1234567890ABCDEF12345678 /* Debug */ = {\n"
                    "\t\t\tisa = XCBuildConfiguration;\n"
                    "\t\t\tbuildSettings = {\n"
                    "\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 10.13;\n"
                    "\t\t\t};\n\t\t};\n"
                )
            self.sources.append(write(self.root / path, contents))
        self.sources.append(write(
            self.root / "submodules/telegram-ios/submodules/TelegramCore/Package.swift",
            'let target = Target.target(name: "TelegramCore", swiftSettings: [.unsafeFlags(["-warnings-as-errors"])])\n',
        ))
        for name in [
            "packages/CallVideoLayer/Package.swift",
            "packages/DustLayer/Package.swift",
            "submodules/telegram-ios/submodules/MetalEngine/Package.swift",
        ]:
            self.sources.append(write(
                self.root / name,
                'let target = Target.target(name: "Shader", path: "Sources", resources: [.copy("Shader.metal")])\n',
            ))
        write(self.bin / "xcodebuild", '#!/bin/sh\necho "Status: installed"\n', executable=True)
        for command in [
            ["git", "init", "-q", str(self.root)],
            ["git", "-C", str(self.root), "add", "."],
            ["git", "-C", str(self.root), "-c", "user.name=Build Test", "-c", "user.email=build@example.invalid", "commit", "-qm", "fixture"],
        ]:
            subprocess.run(command, check=True, capture_output=True, text=True)

    def snapshot(self):
        return {path: path.read_bytes() for path in self.sources}

    def test_mtproto_apply_is_idempotent_and_revert_preserves_other_changes(self):
        before = self.snapshot()
        project = self.root / MTPROTO_PROJECT
        original = project.read_text()
        original_targets = re.findall(r"MACOSX_DEPLOYMENT_TARGET = ([^;]+);", original)
        self.assertTrue(original_targets)
        self.assertTrue(all(value == "10.13" for value in original_targets))

        result = self.run_script("xcode27.sh", "apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            re.findall(r"MACOSX_DEPLOYMENT_TARGET = ([^;]+);", project.read_text()),
            ["12.0"] * len(original_targets),
        )
        applied = self.snapshot()
        result = self.run_script("xcode27.sh", "apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.snapshot(), applied)

        self.assertIn("CURRENT_PROJECT_VERSION = 1;", project.read_text())
        project.write_text(project.read_text().replace("CURRENT_PROJECT_VERSION = 1;", "CURRENT_PROJECT_VERSION = 2;"))
        result = self.run_script("xcode27.sh", "revert")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        before[project] = original.replace("CURRENT_PROJECT_VERSION = 1;", "CURRENT_PROJECT_VERSION = 2;").encode()
        self.assertEqual(self.snapshot(), before)
        result = self.run_script("xcode27.sh", "revert")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.snapshot(), before)


if __name__ == "__main__":
    unittest.main()
