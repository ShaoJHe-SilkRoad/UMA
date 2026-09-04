#!/usr/bin/env python3
"""Exercise development package refusal before any compiler or output write."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class DevelopmentPackageGuards(unittest.TestCase):
    def test_unsafe_overrides_leave_fixture_bytes_unchanged(self):
        script = Path(__file__).resolve().with_name("package_uma014_m1_dev.sh")
        with tempfile.TemporaryDirectory(prefix="uma014-package-guards-") as temporary:
            root = Path(temporary).resolve()
            package = root / "packages"
            existing = package / "Accepted Review.app"
            existing.mkdir(parents=True)
            sentinel = existing / "accepted-bytes"
            sentinel.write_bytes(b"protected fixture")
            alias = root / "alias"
            alias.symlink_to(package, target_is_directory=True)
            environment = {
                key: value for key, value in os.environ.items()
                if not key.startswith("UMA014_") and key not in (
                    "CLANG_MODULE_CACHE_PATH", "SWIFTPM_MODULECACHE_OVERRIDE"
                )
            }
            environment.update(
                UMA014_M1_BUILD_ROOT=str(root / "build"),
                UMA014_M1_PACKAGE_ROOT=str(package),
                UMA014_APPLICATION_NAME="Fixture Dev",
                UMA014_BUNDLE_IDENTIFIER="com.silkrd.uma.dev.m5b-fixture",
            )
            cases = [
                ({"UMA014_BUNDLE_IDENTIFIER": "com.silkrd.uma"}, "DEVELOPMENT_ID_REQUIRED"),
                ({"UMA014_BUNDLE_IDENTIFIER": "com.silkrd.uma.test"}, "DEVELOPMENT_ID_REQUIRED"),
                ({"UMA014_BUNDLE_IDENTIFIER": "com.silkrd.uma.dev."}, "DEVELOPMENT_ID_REQUIRED"),
                ({"UMA014_APPLICATION_NAME": "../Escape"}, "APPLICATION_NAME_INVALID"),
                ({"UMA014_APPLICATION_NAME": "Bad\nName"}, "APPLICATION_NAME_INVALID"),
                ({"UMA014_APPLICATION_NAME": "Accepted Review"}, "ARTIFACT_ALREADY_EXISTS"),
                ({"UMA014_M1_PACKAGE_ROOT": "relative"}, "OUTPUT_PATH_INVALID"),
                ({"UMA014_M1_PACKAGE_ROOT": "//"}, "OUTPUT_PATH_INVALID"),
                ({"UMA014_M1_BUILD_ROOT": "///"}, "OUTPUT_PATH_INVALID"),
                ({"UMA014_M1_PACKAGE_ROOT": str(package / ".." / "elsewhere")}, "OUTPUT_PATH_INVALID"),
                ({"UMA014_M1_PACKAGE_ROOT": str(alias / "new")}, "OUTPUT_SYMLINK_REJECTED"),
                ({"UMA014_M1_BUILD_ROOT": str(existing / "build")}, "OUTPUT_PATH_INVALID"),
                ({"UMA014_M1_PACKAGE_ROOT": str(root / "Protected.APP" / "nested")}, "OUTPUT_PATH_INVALID"),
                ({"UMA014_M1_BUILD_NUMBER": "0"}, "BUILD_NUMBER_INVALID"),
            ]
            before = sorted(str(path.relative_to(root)) for path in root.rglob("*"))
            for overrides, marker in cases:
                with self.subTest(overrides=overrides):
                    result = subprocess.run(
                        ["/bin/bash", str(script)], env=environment | overrides,
                        capture_output=True, text=True, check=False,
                    )
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    self.assertIn("UMA014_" + marker, result.stderr)
                    self.assertEqual(sentinel.read_bytes(), b"protected fixture")
                    self.assertEqual(
                        sorted(str(path.relative_to(root)) for path in root.rglob("*")), before
                    )


if __name__ == "__main__":
    unittest.main()
