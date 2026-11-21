#!/usr/bin/env python3
"""Fail packaging if an embedded Mach-O is encrypted, simulator-only, or requires newer iOS."""
import json
import plistlib
import struct
import sys
from pathlib import Path

MAX_IOS = (16, 0, 0)
ARM64 = 0x0100000C

def version(n):
    return (n >> 16, (n >> 8) & 255, n & 255)

def inspect_macho(data, label):
    magic = data[:4]
    if magic in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        fat64 = magic[-1] == 0xbf
        count = struct.unpack_from('>I', data, 4)[0]
        slices = []
        for i in range(count):
            entry = 8 + i * (32 if fat64 else 20)
            cpu = struct.unpack_from('>I', data, entry)[0]
            offset, size = struct.unpack_from('>QQ' if fat64 else '>II', data, entry + 8)
            if cpu == ARM64:
                slices += inspect_macho(data[offset:offset + size], label)
        if not slices:
            raise ValueError(f'{label}: no arm64 device slice')
        return slices
    if magic not in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe'):
        return []
    cpu, _, _, ncmds = struct.unpack_from('<IIII', data, 4)
    if cpu != ARM64:
        raise ValueError(f'{label}: architecture is not arm64')
    offset = 32 if magic[0] == 0xcf else 28
    minimum = None
    dependencies = []
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError(f'{label}: invalid Mach-O command')
        if cmd == 0x32:  # LC_BUILD_VERSION
            platform, packed = struct.unpack_from('<II', data, offset + 8)
            if platform != 2:
                raise ValueError(f'{label}: platform {platform} is not an iOS device')
            minimum = version(packed)
        elif cmd == 0x25:  # LC_VERSION_MIN_IPHONEOS
            minimum = version(struct.unpack_from('<I', data, offset + 8)[0])
        elif cmd in (0x21, 0x2C):  # LC_ENCRYPTION_INFO[_64]
            if struct.unpack_from('<I', data, offset + 16)[0]:
                raise ValueError(f'{label}: encrypted executable')
        elif cmd in (0xC, 0x80000018, 0x8000001F, 0x20, 0x80000023):
            start = offset + struct.unpack_from('<I', data, offset + 8)[0]
            name = data[start:offset + size].split(b'\0')[0].decode('utf-8')
            dependencies.append(name)
            if any(term in name.lower() for term in ('aether', 'libavcodec', 'libavformat')):
                raise ValueError(f'{label}: removed engine dependency {name}')
        offset += size
    if minimum is None or minimum > MAX_IOS:
        raise ValueError(f'{label}: minimum iOS {minimum}, expected <= {MAX_IOS}')
    return [{'file': label, 'arch': 'arm64', 'minimum_ios': '.'.join(map(str, minimum)), 'dependencies': dependencies}]

def validate(app):
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    minimum = tuple(int(n) for n in info['MinimumOSVersion'].split('.'))
    if minimum + (0,) * (3 - len(minimum)) > MAX_IOS:
        raise ValueError('Info.plist requires newer than iOS 16.0')
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('Not an iPhoneOS device application')
    executable = app / info['CFBundleExecutable']
    main = inspect_macho(executable.read_bytes(), executable.name)
    if not main:
        raise ValueError('App executable is not Mach-O')
    binaries = list(main)
    for p in app.rglob('*'):
        if p.is_file() and p != executable:
            with p.open('rb') as f:
                magic = f.read(4)
            if magic in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
                binaries.extend(inspect_macho(p.read_bytes(), str(p.relative_to(app))))
    return {'bundle_id': info['CFBundleIdentifier'], 'minimum_ios': info['MinimumOSVersion'], 'binaries': binaries}

if __name__ == '__main__':
    print(json.dumps(validate(Path(sys.argv[1])), indent=2))
