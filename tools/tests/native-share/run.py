from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'TelegramShare/SEFoldersRowItem.swift').read_text()
start = source.index('private struct SEFolderTitleEmoji {')
end = source.index('private final class SEFolderTitleView:', start)
with tempfile.TemporaryDirectory(prefix='native-share-tests-') as directory:
    directory = Path(directory)
    fixture = directory / 'main.swift'
    fixture.write_text('import Cocoa\n' + (Path(__file__).parent / 'Support.swift').read_text() + source[start:end] + (Path(__file__).parent / 'TitleTests.swift').read_text())
    executable = directory / 'native-share-tests'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'modules'), str(fixture), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)

products = (root / '.build/Telegram-latest.app').resolve().parent
if not (products / 'SwiftSignalKit.o').exists():
    products = root / '.build/AppDerivedData/Build/Products/Debug'
controller = (root / 'TelegramShare/SESelectController.swift').read_text()
start = controller.index('private func shareFolderPreferences(')
end = controller.index('private final class Container', start)
with tempfile.TemporaryDirectory(prefix='native-share-refresh-tests-') as directory:
    directory = Path(directory)
    fixture = directory / 'main.swift'
    fixture.write_text((Path(__file__).parent / 'FolderRefreshSupport.swift').read_text() + controller[start:end] + (Path(__file__).parent / 'FolderRefreshTests.swift').read_text())
    executable = directory / 'native-share-refresh-tests'
    if (products / 'SwiftSignalKit.o').exists():
        dependencies = ['-I', str(products), str(products / 'SwiftSignalKit.o')]
    else:
        sources = sorted((root / 'submodules/telegram-ios/submodules/SSignalKit/SwiftSignalKit2/Source').glob('*.swift'))
        if not sources:
            raise SystemExit('Initialize submodules/telegram-ios and its submodules/SSignalKit before running these tests.')
        library = directory / 'libSwiftSignalKit.dylib'
        subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'modules'), '-emit-library', '-emit-module', '-module-name', 'SwiftSignalKit', '-emit-module-path', str(directory / 'SwiftSignalKit.swiftmodule'), *map(str, sources), '-o', str(library)], check=True)
        dependencies = ['-I', str(directory), str(library)]
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'modules'), *dependencies, str(fixture), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
