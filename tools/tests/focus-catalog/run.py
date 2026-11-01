from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
source = (root / "Telegram-Mac/account/FocusCatalogProjection.swift").read_text()
source = "\n".join(line for line in source.splitlines() if not line.startswith("import "))
core = sorted((root / "packages/FocusFilterCore/Sources/FocusFilterCore").glob("*.swift"))

with tempfile.TemporaryDirectory(prefix="focus-catalog-tests-") as directory:
    directory = Path(directory)
    adapter = directory / "CatalogAdapter.swift"
    adapter.write_text("import Foundation\n" + source)
    executable = directory / "FocusCatalogTests"
    subprocess.run([
        "xcrun", "swiftc", "-module-cache-path", str(directory / "ModuleCache"),
        *(str(path) for path in core),
        str(adapter), str(Path(__file__).with_name("FocusCatalogTests.swift")),
        "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)
