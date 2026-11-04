"""Import Apple signing into a temporary CI keychain, export and verify an IPA."""
import base64
from datetime import datetime, timezone
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
import zipfile


def command(args):
    result = subprocess.run(args, capture_output=True)
    if result.returncode:
        raise SystemExit(result.stderr.decode(errors='replace'))
    return result.stdout


def required(name):
    value = os.environ.get(name, '')
    if not value:
        raise SystemExit(f'Missing required signing value: {name}')
    return value


def work_directory():
    return Path(required('RUNNER_TEMP')) / 'cf-monitor-signing'


def profile_info(profile, bundle_id):
    expiration = profile['ExpirationDate'].replace(tzinfo=timezone.utc)
    if expiration <= datetime.now(timezone.utc):
        raise ValueError('The provisioning profile has expired.')
    entitlements = profile['Entitlements']
    team = profile['TeamIdentifier'][0]
    app_identifier = entitlements['application-identifier']
    if not fnmatch.fnmatchcase(f'{team}.{bundle_id}', app_identifier):
        raise ValueError('The provisioning profile does not match this app bundle ID.')
    if profile.get('ProvisionsAllDevices'):
        method = 'enterprise'
    elif entitlements.get('get-task-allow'):
        method = 'debugging'
    elif profile.get('ProvisionedDevices'):
        method = 'release-testing'
    else:
        method = 'app-store-connect'
    return team, method


def configure_project(bundle_id, team, identity, uuid):
    project = Path('ios/Runner.xcodeproj/project.pbxproj')
    document = json.loads(command(['plutil', '-convert', 'json', '-o', '-', str(project)]))
    objects = document['objects']
    target = next(value for value in objects.values()
                  if value.get('isa') == 'PBXNativeTarget' and value.get('name') == 'Runner')
    configurations = objects[target['buildConfigurationList']]['buildConfigurations']
    text = project.read_text()
    settings = {
        'CODE_SIGN_STYLE': 'Manual',
        'CODE_SIGN_IDENTITY': identity,
        'DEVELOPMENT_TEAM': team,
        'PROVISIONING_PROFILE_SPECIFIER': uuid,
        'PRODUCT_BUNDLE_IDENTIFIER': bundle_id,
    }
    for config_id in configurations:
        pattern = re.compile(
            rf'(^\t\t{re.escape(config_id)} /\*[^\n]+\n.*?^\t\t\tbuildSettings = \{{\n)'
            r'(.*?)(^\t\t\t\};)', re.M | re.S)
        def replace(match):
            body = match[2]
            for key, value in settings.items():
                body = re.sub(rf'^\t{{4}}{key}(?:\[[^\]]+\])? = .*?;\n', '', body, flags=re.M)
                body += f'\t\t\t\t{key} = "{value}";\n'
            return match[1] + body + match[3]
        text, count = pattern.subn(replace, text)
        if count != 1:
            raise ValueError('Cannot configure the Runner signing settings.')
    project.write_text(text)


def prepare():
    os.umask(0o077)
    directory = work_directory()
    directory.mkdir(parents=True, exist_ok=True)
    certificate = directory / 'certificate.p12'
    profile_file = directory / 'profile.mobileprovision'
    certificate.write_bytes(base64.b64decode(required('IOS_CERTIFICATE_BASE64'), validate=True))
    profile_file.write_bytes(base64.b64decode(required('IOS_PROVISIONING_PROFILE_BASE64'), validate=True))
    password = required('IOS_CERTIFICATE_PASSWORD')
    bundle_id = required('IOS_BUNDLE_ID')
    profile = plistlib.loads(command(['security', 'cms', '-D', '-i', str(profile_file)]))
    team, method = profile_info(profile, bundle_id)
    uuid = profile['UUID']
    if not re.fullmatch(r'[A-Za-z0-9-]+', uuid):
        raise ValueError('Invalid profile UUID.')
    original_keychains = shlex.split(command(['security', 'list-keychains', '-d', 'user']).decode())
    state = {'keychains': original_keychains, 'profiles': [], 'bundle_id': bundle_id}
    state_file = directory / 'state.json'
    state_file.write_text(json.dumps(state))
    keychain = str(directory / 'signing.keychain-db')
    keychain_password = secrets.token_hex(24)
    print(f'::add-mask::{keychain_password}', flush=True)
    command(['security', 'create-keychain', '-p', keychain_password, keychain])
    command(['security', 'set-keychain-settings', '-lut', '21600', keychain])
    command(['security', 'unlock-keychain', '-p', keychain_password, keychain])
    command(['security', 'list-keychains', '-d', 'user', '-s', keychain, *original_keychains])
    command(['security', 'import', str(certificate), '-P', password, '-k', keychain,
             '-T', '/usr/bin/codesign', '-T', '/usr/bin/security'])
    command(['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:',
             '-s', '-k', keychain_password, keychain])
    identities = command(['security', 'find-identity', '-v', '-p', 'codesigning', keychain]).decode()
    fingerprints = {hashlib.sha1(data).hexdigest().upper() for data in profile['DeveloperCertificates']}
    identity = next((value for value in re.findall(r'\b([A-F0-9]{40})\b', identities)
                     if value in fingerprints), None)
    if identity is None:
        raise ValueError('The imported identity is not valid for this provisioning profile.')
    for relative in ['Library/MobileDevice/Provisioning Profiles',
                     'Library/Developer/Xcode/UserData/Provisioning Profiles']:
        folder = Path.home() / relative
        folder.mkdir(parents=True, exist_ok=True)
        target = folder / f'{uuid}.mobileprovision'
        if target.exists():
            raise ValueError('Refusing to overwrite an existing profile on the runner.')
        state['profiles'].append(str(target))
        state_file.write_text(json.dumps(state))
        shutil.copyfile(profile_file, target)
    configure_project(bundle_id, team, identity, uuid)
    export_options = {
        'method': method,
        'teamID': team,
        'signingStyle': 'manual',
        'signingCertificate': identity,
        'provisioningProfiles': {bundle_id: uuid},
        'manageAppVersionAndBuildNumber': False,
    }
    (directory / 'ExportOptions.plist').write_bytes(plistlib.dumps(export_options))
    state.update({'identity': identity, 'team': team, 'uuid': uuid})
    state_file.write_text(json.dumps(state))
    print(f'Configured Apple signing for {bundle_id}; export method: {method}.')


def verify():
    state = json.loads((work_directory() / 'state.json').read_text())
    ipas = list(Path('build/ios/ipa').glob('*.ipa'))
    if len(ipas) != 1:
        raise ValueError(f'Expected one exported IPA, found {len(ipas)}.')
    with tempfile.TemporaryDirectory() as temporary:
        with zipfile.ZipFile(ipas[0]) as archive:
            archive.extractall(temporary)
        apps = list((Path(temporary) / 'Payload').glob('*.app'))
        if len(apps) != 1:
            raise ValueError('The IPA does not contain exactly one application.')
        app = apps[0]
        command(['codesign', '--verify', '--deep', '--strict', str(app)])
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        if info['CFBundleIdentifier'] != state['bundle_id']:
            raise ValueError('The exported IPA has an unexpected bundle identifier.')
        profile = plistlib.loads(command(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')]))
        profile_info(profile, state['bundle_id'])
        if profile['UUID'] != state['uuid']:
            raise ValueError('The exported IPA has an unexpected provisioning profile.')
        prefix = str(Path(temporary) / 'signer-')
        command(['codesign', '--display', '--extract-certificates', prefix, str(app)])
        fingerprint = hashlib.sha1(Path(prefix + '0').read_bytes()).hexdigest().upper()
        if fingerprint != state['identity']:
            raise ValueError('The exported IPA has an unexpected signing certificate.')
    print(f'Verified signature, bundle ID, and provisioning profile: {ipas[0].name}')


def cleanup():
    directory = work_directory()
    state_file = directory / 'state.json'
    if state_file.exists():
        state = json.loads(state_file.read_text())
        command(['security', 'list-keychains', '-d', 'user', '-s', *state['keychains']])
        for profile in state['profiles']:
            Path(profile).unlink(missing_ok=True)
    keychain = directory / 'signing.keychain-db'
    if keychain.exists():
        command(['security', 'delete-keychain', str(keychain)])
    shutil.rmtree(directory, ignore_errors=True)


if __name__ == '__main__':
    {'prepare': prepare, 'verify': verify, 'cleanup': cleanup}[sys.argv[1]]()
