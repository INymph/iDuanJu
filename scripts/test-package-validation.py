import importlib.util
import plistlib
import struct
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('validator', Path(__file__).with_name('verify-ios16-package.py'))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

def binary(ios=16, platform=2, encrypted=False, dependency=None):
    commands = [struct.pack('<IIIIII', 0x32, 24, platform, ios << 16, 18 << 16, 0)]
    if encrypted:
        commands.append(struct.pack('<IIIIII', 0x2c, 24, 0, 0, 1, 0))
    if dependency:
        name = dependency.encode() + b'\0'
        commands.append(struct.pack('<IIIIII', 0xc, 24 + len(name), 24, 0, 0, 0) + name)
    return struct.pack('<IIIIIIII', 0xfeedfacf, validator.ARM64, 0, 2, len(commands), sum(map(len, commands)), 0, 0) + b''.join(commands)

class PackageValidationTests(unittest.TestCase):
    def test_accepts_ios16_binary_built_with_newer_sdk(self):
        self.assertEqual(validator.inspect_macho(binary(), 'STV')[0]['minimum_ios'], '16.0.0')

    def test_rejects_ios18_minimum(self):
        with self.assertRaisesRegex(ValueError, 'minimum iOS'):
            validator.inspect_macho(binary(ios=18), 'STV')

    def test_rejects_simulator(self):
        with self.assertRaisesRegex(ValueError, 'not an iOS device'):
            validator.inspect_macho(binary(platform=7), 'STV')

    def test_rejects_encryption(self):
        with self.assertRaisesRegex(ValueError, 'encrypted'):
            validator.inspect_macho(binary(encrypted=True), 'STV')

    def test_rejects_old_engine_dependency(self):
        with self.assertRaisesRegex(ValueError, 'removed engine'):
            validator.inspect_macho(binary(dependency='@rpath/AetherLibavcodec.framework/AetherLibavcodec'), 'STV')

    def test_checks_embedded_frameworks(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / 'STV.app'
            app.mkdir()
            (app / 'Info.plist').write_bytes(plistlib.dumps({'MinimumOSVersion': '16.0', 'CFBundleSupportedPlatforms': ['iPhoneOS'], 'CFBundleExecutable': 'STV', 'CFBundleIdentifier': 'com.local.STV'}))
            (app / 'STV').write_bytes(binary())
            framework = app / 'Frameworks/Example.framework'
            framework.mkdir(parents=True)
            (framework / 'Example').write_bytes(binary(ios=17))
            with self.assertRaisesRegex(ValueError, 'minimum iOS'):
                validator.validate(app)
            (framework / 'Example').write_bytes(binary(ios=12))
            self.assertEqual(len(validator.validate(app)['binaries']), 2)

if __name__ == '__main__':
    unittest.main()
