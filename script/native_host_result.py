#!/usr/bin/env python3
"""Validate one opt-in native test result from both real helper streams."""
import argparse
import json
from pathlib import Path

def validate(stdout: Path, stderr: Path, lifecycle: Path, readiness: Path,
             expected_bundle: Path, case: str) -> None:
    assert case == 'attachedProductionWindowKeyboardAcceptance', 'unexpected native case'
    assert stdout.is_file() and stderr.is_file(), 'native helper output stream missing'
    combined = stdout.read_text(errors='replace') + '\n' + stderr.read_text(errors='replace')
    expected_case = f'Test {case}() passed'
    assert expected_case in combined, 'selected native case has no passing completion'
    assert 'Test run with 1 test in 1 suite passed' in combined, 'complete one-case pass summary missing'
    assert 'Test run with 1 test in 1 suite failed' not in combined, 'failed run summary present'
    assert 'recorded an issue' not in combined, 'Swift Testing recorded an issue'
    assert lifecycle.is_file(), 'native lifecycle record missing'
    state = json.loads(lifecycle.read_text())
    assert state['fixtureFinished'] is True, 'native fixture did not finish'
    assert state['watchdogFired'] is False, 'native watchdog fired'
    assert state.get('fixtureError') is None, 'native fixture error present'
    assert state.get('deadlineWriteError') is None, 'native deadline write error present'
    assert readiness.is_file(), 'native host readiness record missing'
    host = json.loads(readiness.read_text())
    assert host['exactIdentityMatched'] is True, 'native host identity did not match'
    assert host['expectedBundlePath'] == str(expected_bundle.resolve()), 'native host path differs'

def main() -> None:
    parser = argparse.ArgumentParser()
    for name in ('stdout', 'stderr', 'lifecycle', 'readiness', 'expected-bundle'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--case', required=True)
    args = parser.parse_args()
    validate(args.stdout, args.stderr, args.lifecycle, args.readiness,
             args.expected_bundle, args.case)
    print('Native helper selected test, complete summary, identity and lifecycle passed.')

if __name__ == '__main__':
    main()
