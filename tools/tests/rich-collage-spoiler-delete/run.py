import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

BASE = '246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5'
CORE_PIN = '24638bc69bd083981b178dd1e7f921eebbf7fc46'
SOURCE = 'packages/RichTextEditorUI/Sources/RichTextEditorUI/Canvas/DocumentCanvasView+MediaGroup.swift'
MODEL = 'packages/RichTextEditorUI/Sources/RichTextEditorUI/Model/MediaBlock.swift'
CORE_MODEL = 'submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorCore/Model/'
MODELS = ['BlockID', 'RGBAColor', 'Enums', 'CharacterAttributes', 'EmojiRef', 'ButtonRef', 'TextRun', 'ParagraphAttributes', 'ListMembership', 'ParagraphBlock', 'TableBlock', 'Block', 'CodeBlock', 'PullQuote', 'BlockQuote', 'DetailsBlock', 'MediaBlock', 'MediaItem', 'MediaKind', 'Size2D', 'Document']


def block(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    depth = 0
    for end in range(opening, len(text)):
        depth += (text[end] == '{') - (text[end] == '}')
        if depth == 0:
            return text[start:end + 1]
    raise ValueError(marker)


def main():
    assert sys.flags.isolated
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compiler-lock', type=Path)
    args = parser.parse_args()
    source = args.source_root.resolve()
    repo = Path(__file__).resolve().parents[3]
    output = args.output.resolve()
    assert all(output != p and p not in output.parents for p in (source, repo))
    output.mkdir(parents=True, exist_ok=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    env['CLANG_MODULE_CACHE_PATH'] = str(output / 'modules')
    common = Path(subprocess.check_output(['git', '-C', str(repo), 'rev-parse', '--git-common-dir'], text=True).strip())
    if not common.is_absolute():
        common = (repo / common).resolve()
    core_git = common / 'modules/submodules/telegram-ios'
    models = output / 'models'
    models.mkdir(exist_ok=True)
    model_paths = []
    report = {'base': BASE, 'core_pin': CORE_PIN, 'models': {}, 'variants': {}}
    for name in MODELS:
        path = CORE_MODEL + name + '.swift'
        raw = subprocess.check_output(['git', '--git-dir=' + str(core_git), 'show', CORE_PIN + ':' + path], env=env)
        target = models / (name + '.swift')
        target.write_bytes(raw)
        model_paths.append(str(target))
        report['models'][path] = hashlib.sha256(raw).hexdigest()
    compiler = shutil.which('swiftc')
    lock_path = args.compiler_lock or output / 'compiler.lock'
    def compile_swift(command, folder):
        with lock_path.open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            result = subprocess.run(command, cwd=folder, env=env, text=True, capture_output=True)
        (folder / 'compile.log').write_text(result.stdout + result.stderr)
        assert result.returncode == 0, str(folder / 'compile.log')
    library = models / 'libRichTextEditorCore.dylib'
    compile_swift([compiler, '-j1', '-module-cache-path', str(output / 'modules'), '-emit-library', '-emit-module', '-module-name', 'RichTextEditorCore', *model_paths, '-o', str(library), '-emit-module-path', str(models / 'RichTextEditorCore.swiftmodule')], models)
    template = Path(__file__).with_name('Regression.swift.in').read_text()
    for variant in ('fixed', 'baseline'):
        folder = output / variant
        folder.mkdir(exist_ok=True)
        def read(name):
            if variant == 'fixed':
                return (source / name).read_text()
            return subprocess.check_output(['git', '-C', str(repo), 'show', BASE + ':' + name], text=True, env=env)
        production = read(SOURCE)
        model = read(MODEL)
        hosted = read('packages/RichTextEditorUI/Sources/RichTextEditorUI/Canvas/DocumentCanvasView+MediaBlocks.swift')
        code = template.replace('@@REMOVE@@', block(production, '    func removeCollageTile(')).replace('@@HOSTED@@', block(hosted, 'final class HostedMediaBlock {')).replace('@@TILES@@', block(production, '            for (i, tile) in frames.enumerated() where i < box.mediaIDs.count {'))
        (folder / 'main.swift').write_text(code)
        (folder / 'MediaBlock.swift').write_text(model)
        binary = folder / 'regression'
        command = [compiler, '-j1', '-module-cache-path', str(output / 'modules'), '-I', str(models), '-L', str(models), '-lRichTextEditorCore', '-Xlinker', '-rpath', '-Xlinker', str(models), str(folder / 'MediaBlock.swift'), str(folder / 'main.swift'), '-o', str(binary)]
        compile_swift(command, folder)
        result = subprocess.run([str(binary)], cwd=folder, env=env, text=True, capture_output=True)
        (folder / 'run.log').write_text(result.stdout + result.stderr)
        passed = sum(x.startswith('PASS ') for x in result.stdout.splitlines())
        failed = sum(x.startswith('FAIL ') for x in result.stdout.splitlines())
        report['variants'][variant] = {'compiled': True, 'passed': passed, 'failed': failed, 'exit': result.returncode, 'source_sha256': hashlib.sha256(production.encode()).hexdigest(), 'model_sha256': hashlib.sha256(model.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(code.encode()).hexdigest(), 'command': command}
        print(variant, passed, 'passed', failed, 'failed', flush=True)
        assert (result.returncode == 0 and passed and failed == 0) if variant == 'fixed' else (result.returncode == 1 and failed > 0)
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
