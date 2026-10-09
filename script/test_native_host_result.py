import json
import tempfile
import unittest
from pathlib import Path
from native_host_result import validate

CASE = 'attachedProductionWindowKeyboardAcceptance'
PASS = f'✔ Test {CASE}() passed after 0.1 seconds.\n✔ Test run with 1 test in 1 suite passed after 0.1 seconds.\n'

class NativeHostResultTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='uma015-native-result-')
        self.root = Path(self.directory.name)
        self.bundle = self.root / 'host/UMA015NativeTestHost.app'
        self.bundle.mkdir(parents=True)
        self.stdout = self.root / 'stdout.log'
        self.stderr = self.root / 'stderr.log'
        self.stdout.write_text('')
        self.stderr.write_text(PASS)
        self.lifecycle = self.root / 'lifecycle.json'
        self.lifecycle.write_text(json.dumps({'fixtureFinished': True, 'watchdogFired': False,
            'fixtureError': None, 'deadlineWriteError': None}))
        self.readiness = self.root / 'readiness.json'
        self.readiness.write_text(json.dumps({'exactIdentityMatched': True,
            'expectedBundlePath': str(self.bundle.resolve())}))

    def tearDown(self):
        self.directory.cleanup()

    def check(self):
        validate(self.stdout, self.stderr, self.lifecycle, self.readiness, self.bundle, CASE)

    def test_complete_pass_in_stderr(self):
        self.check()

    def test_complete_pass_in_stdout(self):
        self.stdout.write_text(PASS)
        self.stderr.write_text('')
        self.check()

    def test_failed_summary_rejected(self):
        self.stderr.write_text(PASS + '✘ Test run with 1 test in 1 suite failed after 0.1 seconds.\n')
        with self.assertRaises(AssertionError): self.check()

    def test_missing_selected_case_rejected(self):
        self.stderr.write_text('✔ Test run with 1 test in 1 suite passed after 0.1 seconds.\n')
        with self.assertRaises(AssertionError): self.check()

    def test_incomplete_summary_rejected(self):
        self.stderr.write_text(f'✔ Test {CASE}() passed after 0.1 seconds.\n')
        with self.assertRaises(AssertionError): self.check()

    def test_actual_clean_swift_lifecycle_omits_optional_errors(self):
        self.lifecycle.write_text(json.dumps({'appRunningAfterFixture': False,
            'appWasRunningAtEntry': False, 'fixtureFinished': True,
            'watchdogFired': False}))
        self.check()

    def test_missing_required_lifecycle_rejected(self):
        self.lifecycle.write_text(json.dumps({'watchdogFired': False}))
        with self.assertRaises(KeyError): self.check()

    def test_deadline_write_error_rejected(self):
        self.lifecycle.write_text(json.dumps({'fixtureFinished': True,
            'watchdogFired': False, 'deadlineWriteError': 'write failed'}))
        with self.assertRaises(AssertionError): self.check()

    def test_fixture_error_rejected(self):
        self.lifecycle.write_text(json.dumps({'fixtureFinished': True, 'watchdogFired': False,
            'fixtureError': 'failed', 'deadlineWriteError': None}))
        with self.assertRaises(AssertionError): self.check()

    def test_watchdog_rejected(self):
        self.lifecycle.write_text(json.dumps({'fixtureFinished': True, 'watchdogFired': True,
            'fixtureError': None, 'deadlineWriteError': None}))
        with self.assertRaises(AssertionError): self.check()

    def test_wrong_identity_rejected(self):
        self.readiness.write_text(json.dumps({'exactIdentityMatched': False,
            'expectedBundlePath': str(self.bundle.resolve())}))
        with self.assertRaises(AssertionError): self.check()

if __name__ == '__main__':
    unittest.main()
