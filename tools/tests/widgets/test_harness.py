from copy import deepcopy
from pathlib import Path
import hashlib
import contextlib
import io
import json
import random
import tempfile
import unittest
from unittest.mock import MagicMock, patch
import zlib

from pack import pack
from run import Runner, audit_stress, audit_conformance, audit_expectations, audit_node_tests, audit_playwright, audit_xctest, stop_process_group


class PackageTests(unittest.TestCase):
    def test_zlib_utf8_and_manifest_are_deterministic(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'probe.html'
            output = Path(directory) / 'probe.tgw'
            raw = '<p>Привет 👋</p>'.encode()
            source.write_bytes(raw)
            first = pack(source, output)
            payload = output.read_bytes()
            self.assertEqual(zlib.decompress(payload), raw)
            self.assertEqual(first, pack(source, output))
            self.assertEqual(payload, output.read_bytes())
            self.assertEqual(first['htmlSha256'], hashlib.sha256(raw).hexdigest())
            self.assertEqual(first['sha256'], hashlib.sha256(payload).hexdigest())
            self.assertEqual(json.loads(output.with_suffix('.manifest.json').read_text()), first)

    def test_rejects_invalid_sources_without_writing(self):
        noise = random.Random(0)
        invalid = [b'', b'\xff', b'<p>\0</p>', b'x' * 32769, bytes(noise.randrange(32, 127) for _ in range(32000))]
        for raw in invalid:
            with self.subTest(size=len(raw)), tempfile.TemporaryDirectory() as directory:
                source = Path(directory) / 'probe.html'
                output = Path(directory) / 'probe.tgw'
                source.write_bytes(raw)
                with self.assertRaises((UnicodeError, ValueError)):
                    pack(source, output)
                self.assertFalse(output.exists())

    def test_accepts_exact_raw_limit(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'probe.html'
            source.write_bytes(b'x' * 32768)
            self.assertEqual(pack(source, source.with_suffix('.tgw'))['htmlBytes'], 32768)

    def test_rejects_wrong_extension_and_overwriting_source(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'probe.tgw'
            source.write_text('<p>source</p>')
            for output in [source.with_suffix('.gzip'), source]:
                with self.assertRaises(ValueError):
                    pack(source, output)
            self.assertEqual(source.read_text(), '<p>source</p>')


class VerdictTests(unittest.TestCase):
    def setUp(self):
        self.manifest = {'tests': [{'id': 'auto/probe', 'set': 'auto', 'themes': ['light', 'dark'], 'stages': [{'name': 'box', 'themes': ['light', 'dark']}]}]}
        self.run = {'runs': [{'id': 'auto/probe', 'theme': theme, 'width': 390, 'loaded': True, 'dead': None, 'status': 'done', 'checks': [['feature', 'probe', 'pass', '']], 'stages': [{'name': 'box', 'crop': f'{theme}.png'}]} for theme in ['light', 'dark']]}

    def test_complete_pass(self):
        self.assertEqual(audit_conformance(self.run, self.manifest), [])

    def test_expected_limit_stop_passes_before_loaded_or_done(self):
        self.manifest['tests'][0]['stops'] = 'Text limit exceeded'
        for row in self.run['runs']:
            row.update(loaded=False, dead='Text limit exceeded: 40000 characters', status='none', checks=[], stages=[])
        self.assertEqual(audit_conformance(self.run, self.manifest), [])

    def test_expected_limit_stop_rejects_survival_and_other_deaths(self):
        self.manifest['tests'][0]['stops'] = 'Text limit exceeded'
        for reason in [None, '', 'CPU quota exceeded', 'Error: Text limit exceeded']:
            run = deepcopy(self.run)
            for row in run['runs']:
                row['dead'] = reason
            with self.subTest(reason=reason):
                self.assertTrue(audit_conformance(run, self.manifest))

    def test_expected_stop_keeps_error_and_missing_run_checks(self):
        self.manifest['tests'][0]['stops'] = 'Text limit exceeded'
        for row in self.run['runs']:
            row.update(dead='Text limit exceeded', checks=[], stages=[])
        self.assertTrue(audit_conformance({'runs': self.run['runs'][:1]}, self.manifest))
        self.run['runs'][0]['errors'] = ['unexpected exception']
        self.assertTrue(audit_conformance(self.run, self.manifest))

    def test_rejects_empty_partial_duplicate_and_wrong_width_runs(self):
        variants = [{'runs': []}, {'runs': self.run['runs'][:1]}, {'runs': self.run['runs'] * 2}]
        wrong_width = deepcopy(self.run)
        wrong_width['runs'][0]['width'] = 360
        variants.append(wrong_width)
        for run in variants:
            with self.subTest(run=run):
                self.assertTrue(audit_conformance(run, self.manifest))

    def test_rejects_dead_pending_failed_and_unexecuted_checks(self):
        for changes in [{'loaded': False}, {'dead': 'cpu'}, {'status': 'awaiting'}, {'checks': []}, {'errors': ['exception']}, {'skippedActions': [0]}]:
            run = deepcopy(self.run)
            run['runs'][0].update(changes)
            with self.subTest(changes=changes):
                self.assertTrue(audit_conformance(run, self.manifest))
        for verdict in ['fail', 'pending', 'xpass']:
            run = deepcopy(self.run)
            run['runs'][0]['checks'][0][2] = verdict
            self.assertTrue(audit_conformance(run, self.manifest))

    def test_rejects_missing_pixels(self):
        for stages in [[], [{'name': 'box', 'status': 'skip', 'diff': None}], [{'name': 'box'}]]:
            run = deepcopy(self.run)
            run['runs'][0]['stages'] = stages
            self.assertTrue(audit_conformance(run, self.manifest))

    def test_rejects_skipped_unknown_and_missing_declared_checks(self):
        self.manifest['tests'][0]['checks'] = [{'id': 'feature', 'name': 'probe'}, {'id': 'second', 'name': 'missing'}]
        self.assertTrue(audit_conformance(self.run, self.manifest))
        del self.manifest['tests'][0]['checks']
        for verdict in ['skip', 'unknown']:
            run = deepcopy(self.run)
            run['runs'][0]['checks'][0][2] = verdict
            self.assertTrue(audit_conformance(run, self.manifest))

    def test_pixel_only_widgets_need_pixels_without_self_checks(self):
        self.manifest['tests'][0].update(kind=['pixel'], checks=[])
        for row in self.run['runs']:
            row['checks'] = []
        self.assertEqual(audit_conformance(self.run, self.manifest), [])
        self.run['runs'][0]['stages'] = []
        self.assertTrue(audit_conformance(self.run, self.manifest))

    def test_conditional_sandbox_checks_replace_native_guard_exactly(self):
        self.manifest['tests'][0]['checks'] = [{'id': 'guard', 'name': 'native guard'}]
        expected = {'auto/probe': {'checks': [['feature', 'probe']]}}
        self.assertEqual(audit_conformance(self.run, self.manifest, expected), [])
        expected['auto/probe']['checks'].append(['feature', 'second assertion'])
        self.assertTrue(audit_conformance(self.run, self.manifest, expected))

    def test_platform_skip_requires_pinned_exact_check_and_reason(self):
        expected = {'auto/probe': {'allowedSkips': [['feature', 'probe', 'no touch input here']]}}
        self.manifest['tests'][0]['checks'] = [{'id': 'feature', 'name': 'probe'}]
        for row in self.run['runs']:
            row['checks'] = [['feature', 'probe', 'skip', 'no touch input here']]
        self.assertEqual(audit_conformance(self.run, self.manifest, expected), [])
        self.run['runs'][0]['checks'][0][3] = 'unknown reason'
        self.assertTrue(audit_conformance(self.run, self.manifest, expected))

    def test_changed_conditional_fixture_invalidates_expectations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'test.html'
            source.write_bytes(b'original')
            manifest = {'tests': [{'id': 'auto/probe', 'file': 'test.html'}]}
            expected = {'auto/probe': {'htmlSha256': hashlib.sha256(source.read_bytes()).hexdigest()}}
            self.assertEqual(audit_expectations(expected, manifest, root), [])
            source.write_bytes(b'changed')
            self.assertTrue(audit_expectations(expected, manifest, root))

    def test_rejects_zero_or_only_skipped_native_tests(self):
        self.assertTrue(audit_xctest('Executed 0 tests, with 0 failures (0 unexpected)'))
        self.assertTrue(audit_xctest('Executed 2 tests, with 2 tests skipped and 0 failures (0 unexpected)'))
        self.assertTrue(audit_xctest('No matching test cases were run'))
        self.assertFalse(audit_xctest('Executed 20 tests, with 3 tests skipped and 0 failures (0 unexpected)'))
        self.assertFalse(audit_xctest('Executed 1 test, with 0 failures (0 unexpected)'))

    def test_rejects_unbuilt_node_suites_without_tests(self):
        self.assertTrue(audit_node_tests('ℹ tests 0\nℹ suites 2\nℹ pass 0'))
        self.assertTrue(audit_node_tests('# tests 0\n# pass 0'))
        self.assertTrue(audit_node_tests('No tests found'))
        self.assertEqual(audit_node_tests('ℹ tests 723\nℹ pass 723'), [])

    def test_rejects_skipped_web_specs_and_missing_suites(self):
        report = {'suites': [{'specs': [{'file': 'sdk.spec.ts', 'title': 'SDK', 'tests': [{'expectedStatus': 'passed', 'results': [{'status': 'passed'}]}]}]}]}
        self.assertEqual(audit_playwright(report, ['sdk.spec.ts']), [])
        self.assertTrue(audit_playwright(report, ['sdk.spec.ts', 'activation.spec.ts']))
        test = report['suites'][0]['specs'][0]['tests'][0]
        test.update(expectedStatus='skipped', results=[{'status': 'skipped'}])
        self.assertTrue(audit_playwright(report, ['sdk.spec.ts']))


class StressVerdictTests(unittest.TestCase):
    def setUp(self):
        self.manifest = {'widgets': [{'id': 'dom/100'}, {'id': 'dom/500'}]}
        self.run = {'runs': [{'id': name, 'loaded': True, 'dead': None, 'frames': {}, 'host': {}, 'widget': {'last': {'id': name}}} for name in ('dom/100', 'dom/500')]}

    def test_complete_and_stopped_stress_rows(self):
        self.assertEqual(audit_stress(self.run, self.manifest), [])
        self.run['runs'][1].update(loaded=False, dead='Ops limit exceeded', widget={'last': None})
        self.assertEqual(audit_stress(self.run, self.manifest), [])

    def test_rejects_partial_duplicate_and_unknown_rows(self):
        for rows in [[], self.run['runs'][:1], self.run['runs'] * 2, [dict(self.run['runs'][0], id='old/100')]]:
            self.assertTrue(audit_stress({'runs': rows}, self.manifest))

    def test_rejects_stale_publication_and_absent_metrics(self):
        for change in [{'widget': {'last': {'id': 'old/100'}}}, {'frames': None}, {'host': None}, {'loaded': False}]:
            run = deepcopy(self.run)
            run['runs'][0].update(change)
            self.assertTrue(audit_stress(run, self.manifest))



class ProcessTests(unittest.TestCase):
    def test_cleanup_kills_descendants_after_leader_exits(self):
        process = MagicMock(pid=12345)
        with patch('run.os.killpg') as kill:
            stop_process_group(process)
        self.assertEqual([call.args[0] for call in kill.call_args_list], [12345, 12345])
        self.assertEqual(kill.call_count, 2)

    def test_interruption_preserves_step_and_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runner = Runner(root, root / 'cache', 1)
            process = MagicMock(pid=12345)
            process.wait.side_effect = [KeyboardInterrupt(), 0, 0]
            with patch('run.subprocess.Popen', return_value=process), patch('run.os.killpg'), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(KeyboardInterrupt):
                    runner.step('interrupted', ['child'])
            self.assertEqual(json.loads((root / 'steps.json').read_text())[0]['status'], 'interrupted')
            self.assertEqual(json.loads((root / 'summary.json').read_text())['status'], 'interrupted')


if __name__ == '__main__':
    unittest.main()
