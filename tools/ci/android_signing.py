"""Restore CI-only release signing and verify every APK against that certificate."""
import base64
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys


def command(args):
    result = subprocess.run(args, capture_output=True)
    if result.returncode:
        raise SystemExit(result.stderr.decode(errors='replace'))
    return result.stdout


def required(name):
    value = os.environ.get(name, '')
    if not value:
        raise SystemExit(f'Missing required secret: {name}')
    return value


def property_value(value):
    return (value.replace('\\', '\\\\').replace('\n', '\\n')
            .replace('\r', '\\r').replace('\t', '\\t').replace(' ', '\\ '))


def restore():
    os.umask(0o077)
    values = {
        'storePassword': required('ANDROID_STORE_PASSWORD'),
        'keyPassword': required('ANDROID_KEY_PASSWORD'),
        'keyAlias': required('ANDROID_KEY_ALIAS'),
        'storeFile': 'cf-monitor-release.jks',
    }
    data = base64.b64decode(required('ANDROID_KEYSTORE_BASE64'), validate=True)
    Path('android/cf-monitor-release.jks').write_bytes(data)
    Path('android/key.properties').write_text(''.join(
        f'{key}={property_value(value)}\n' for key, value in values.items()))
    print('Restored Android release signing files.')


def verify():
    required('ANDROID_STORE_PASSWORD')
    certificate = command([
        'keytool', '-exportcert', '-keystore', 'android/cf-monitor-release.jks',
        '-alias', required('ANDROID_KEY_ALIAS'),
        '-storepass:env', 'ANDROID_STORE_PASSWORD',
    ])
    expected = hashlib.sha256(certificate).hexdigest()
    sdk = Path(os.environ.get('ANDROID_SDK_ROOT') or required('ANDROID_HOME'))
    signers = list((sdk / 'build-tools').glob('*/apksigner'))
    if not signers:
        raise SystemExit('Android SDK apksigner is unavailable.')
    signer = max(signers, key=lambda p: tuple(
        int(part) for part in re.findall(r'\d+', p.parent.name)))
    apks = sorted(Path('build/app/outputs/flutter-apk').glob('*-release.apk'))
    if len(apks) != 3:
        raise SystemExit(f'Expected three release APKs, found {len(apks)}.')
    for apk in apks:
        output = command([str(signer), 'verify', '--verbose', '--print-certs', str(apk)]).decode()
        digests = re.findall(r'certificate SHA-256 digest: ([a-fA-F0-9]+)', output)
        if not digests or any(digest.lower() != expected for digest in digests):
            raise SystemExit(f'Unexpected signing certificate: {apk.name}')
        if 'CN=Android Debug' in output:
            raise SystemExit('Refusing an APK signed with an Android debug key.')
        print(f'Verified {apk.name}: SHA-256 {expected}')


if __name__ == '__main__':
    {'restore': restore, 'verify': verify}[sys.argv[1]]()
