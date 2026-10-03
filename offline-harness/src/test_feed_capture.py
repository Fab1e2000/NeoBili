import importlib.util
import json
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[2] / 'scripts/analyze-feed-capture.py'
spec = importlib.util.spec_from_file_location('capture', path)
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)

class FeedCapturePrivacyTests(unittest.TestCase):
    def test_sensitive_unknown_values_and_headers_never_escape(self):
        secret = b'independent-test-secret'
        def row(token):
            return {'query': {k: capture.safe_value(k, token, secret) for k in ['access_key', 'sign', 'ad_extra', 'unknown']},
                    'headers': {'cookie': capture.safe_value('cookie', token, secret)}, 'http_status': 200}
        output = capture.assemble([('cold', [row('fake-sensitive-a')]), ('pull', [row('fake-sensitive-a'), row('fake-sensitive-b')])])
        serialized = json.dumps(output)
        self.assertNotIn('fake-sensitive', serialized)
        self.assertNotIn('redacted', serialized)
        self.assertEqual(output['samples'][0]['query']['access_key'], output['samples'][1]['query']['access_key'])
        self.assertNotEqual(output['samples'][1]['query']['access_key'], output['samples'][2]['query']['access_key'])
        self.assertTrue(all(d['changed'] for d in output['differences']))

    def test_pixel_schema_and_numeric_fields_require_exact_shape(self):
        key = b'test'
        value = capture.safe_value('player_extra_content', '{"short_edge":"750","long_edge":"1334"}', key)
        self.assertEqual(value, {'short_edge':'750', 'long_edge':'1334'})
        value = capture.safe_value('player_extra_content', '{"short_edge":"750","long_edge":"1334","token":"fake-private"}', key)
        self.assertIn('redacted', value)
        self.assertNotIn('fake-private', json.dumps(value))
        self.assertEqual(capture.safe_value('flush', '8', key), '8')
        self.assertIn('redacted', capture.safe_value('flush', 'fake-private', key))

    def test_absent_and_empty_are_distinct_without_treating_stability_as_constant(self):
        row = lambda query: {'query': query, 'headers': {}, 'http_status': 200}
        output = capture.assemble([('cold', [row({'open_event': ''})]), ('pull', [row({})])])
        self.assertTrue(output['differences'][0]['changed'])
        self.assertIn('not proof', output['warning'])

if __name__ == '__main__': unittest.main()
