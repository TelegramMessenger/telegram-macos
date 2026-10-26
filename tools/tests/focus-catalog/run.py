from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
source = (root / "Telegram-Mac/account/FocusFilterCoordinator.swift").read_text()
source = source[source.index("private func focusCatalogTitle"):source.index("private final class FocusAccountCatalogContext")].replace("private func ", "func ")

with tempfile.TemporaryDirectory(prefix="focus-catalog-tests-") as directory:
    directory = Path(directory)
    adapter = directory / "CatalogAdapter.swift"
    adapter.write_text("import Foundation\n" + source)
    executable = directory / "FocusCatalogTests"
    subprocess.run([
        "xcrun", "swiftc", "-module-cache-path", str(directory / "ModuleCache"),
        str(root / "packages/FocusFilterCore/Sources/FocusFilterCore/FocusFilterPolicy.swift"),
        str(adapter), str(Path(__file__).with_name("FocusCatalogTests.swift")),
        "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)
