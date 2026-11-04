from copy import deepcopy
from datetime import datetime, timedelta
import unittest

from android_signing import property_value
from ios_signing import profile_info


class SigningConfigurationTest(unittest.TestCase):
    def setUp(self):
        self.profile = {
            'ExpirationDate': datetime.utcnow() + timedelta(days=1),
            'TeamIdentifier': ['TEAM123456'],
            'Entitlements': {
                'application-identifier': 'TEAM123456.dev.cfmonitor.*',
                'get-task-allow': True,
            },
            'ProvisionedDevices': ['test-device'],
        }

    def test_development_profile_supports_matching_wildcard(self):
        self.assertEqual(profile_info(self.profile, 'dev.cfmonitor.cfMonitorApp'),
                         ('TEAM123456', 'debugging'))

    def test_wrong_application_is_rejected(self):
        with self.assertRaises(ValueError):
            profile_info(self.profile, 'io.github.chaoszhu.easynode')

    def test_expired_profile_is_rejected(self):
        self.profile['ExpirationDate'] = datetime.utcnow() - timedelta(days=1)
        with self.assertRaises(ValueError):
            profile_info(self.profile, 'dev.cfmonitor.cfMonitorApp')

    def test_distribution_profile_selects_correct_export(self):
        self.profile['Entitlements']['get-task-allow'] = False
        self.assertEqual(profile_info(self.profile, 'dev.cfmonitor.cfMonitorApp')[1],
                         'release-testing')
        store = deepcopy(self.profile)
        del store['ProvisionedDevices']
        self.assertEqual(profile_info(store, 'dev.cfmonitor.cfMonitorApp')[1],
                         'app-store-connect')

    def test_properties_preserve_password_whitespace_and_escapes(self):
        self.assertEqual(property_value(' a\\b\nc\rd\te'), r'\ a\\b\nc\rd\te')


if __name__ == '__main__':
    unittest.main()
