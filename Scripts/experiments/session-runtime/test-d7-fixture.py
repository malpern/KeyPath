import importlib.util
import pathlib
import json
import types
import unittest
from unittest.mock import Mock, patch

PATH = pathlib.Path(__file__).with_name('d7-fixture.py')
spec = importlib.util.spec_from_file_location('factory', PATH)
factory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(factory)
RUN = 'session-0123456789abcdef'
SCRIPT = f'KPHID1 {RUN} 2 1 45300000 00000000\n0 0 20 0 0 0 0 0\n45000000 0 0 0 0 0 0 0\n'

class FactoryTests(unittest.TestCase):
    def client(self):
        backend = Mock(token='synthetic-fixture-test-token')
        backend.load_script.return_value = {'ok': True}
        backend.status.return_value = {'ok': True, **factory.EXPECTED_IDENTITY, 'state': 'idle', 'runId': ''}
        client = factory.ScopedClient(backend)
        client.load_script(SCRIPT)
        return client, backend

    def test_construction_only_extracts_selected_scalar_and_has_no_network(self):
        backend = Mock(token='synthetic-fixture-test-token')
        module = types.SimpleNamespace()
        with patch.object(factory, '_module', return_value=module), \
             patch.object(factory, '_selected_token', return_value=backend.token) as selected, \
             patch.object(factory, '_transport', return_value=backend) as transport:
            client = factory.create_client()
        self.assertIsInstance(client, factory.ScopedClient)
        selected.assert_called_once_with()
        transport.assert_called_once_with(module, backend.token)
        backend.status.assert_not_called()

    def test_selected_loader_uses_exact_extract_and_never_exports_token(self):
        result = types.SimpleNamespace(returncode=0, stdout='synthetic-fixture-test-token\n')
        with patch.object(factory.subprocess, 'run', return_value=result) as run, \
             patch.dict(factory.os.environ, {}, clear=True):
            self.assertEqual(factory._selected_token(), 'synthetic-fixture-test-token')
            self.assertNotIn('KEYPATH_FIXTURE_TOKEN', factory.os.environ)
        args, kwargs = run.call_args
        self.assertEqual(args[0][:6], ['/opt/homebrew/bin/sops', '-d', '--extract',
                                     '["KEYPATH_FIXTURE_TOKEN"]', '--output-type', 'json'])
        self.assertEqual(kwargs['timeout'], 10)
        self.assertTrue(kwargs['capture_output'])
        self.assertNotIn('synthetic-fixture-test-token', repr(run.call_args))

    def test_selected_loader_failure_suppresses_outputs_and_never_retries(self):
        for result in (types.SimpleNamespace(returncode=1, stdout='synthetic-sensitive-output'),
                       types.SimpleNamespace(returncode=0, stdout=''),
                       types.SimpleNamespace(returncode=0, stdout='{"foreign":"synthetic-sensitive-output"}')):
            with patch.object(factory.subprocess, 'run', return_value=result) as run:
                with self.assertRaises(RuntimeError) as failure: factory._selected_token()
                run.assert_called_once()
                self.assertNotIn('synthetic-sensitive-output', str(failure.exception))

    def test_only_exact_session_run_namespace_is_accepted(self):
        for run in ('held-secure-0123456789abcdef', 'session-ABCDEF0123456789',
                    'session-0123456789abcde', 'foreign'):
            backend = Mock(token='synthetic-fixture-test-token')
            client = factory.ScopedClient(backend)
            with self.assertRaises(RuntimeError): client.load_script(SCRIPT.replace(RUN, run))
            backend.status.assert_not_called()
            backend.load_script.assert_not_called()

    def test_every_mutation_requires_fresh_matching_identity(self):
        for field in ('ok', *factory.EXPECTED_IDENTITY):
            for operation in ('load_script', 'arm', 'start', 'abort'):
                client, backend = self.client()
                backend.reset_mock()
                bad = {'ok': True, **factory.EXPECTED_IDENTITY,
                       'runId': RUN, 'state': 'running'}
                bad[field] = 'unexpected'
                backend.status.return_value = bad
                with self.assertRaises(RuntimeError):
                    if operation == 'load_script': client.load_script(SCRIPT)
                    elif operation == 'arm': client.arm(RUN)
                    elif operation == 'start': client.start(RUN, 500)
                    else: client.abort()
                backend.status.assert_called_once_with()
                getattr(backend, operation).assert_not_called()

    def test_load_refuses_active_or_unknown_state_without_claiming_run(self):
        for state in ('loaded', 'armed', 'running', 'error', 'unknown', None):
            backend = Mock(token='synthetic-fixture-test-token')
            backend.status.return_value = {'ok': True, **factory.EXPECTED_IDENTITY,
                                           'state': state, 'runId': 'foreign'}
            client = factory.ScopedClient(backend)
            with self.assertRaises(RuntimeError): client.load_script(SCRIPT)
            backend.status.assert_called_once_with()
            backend.load_script.assert_not_called()
            self.assertIsNone(client._run)

    def test_load_accepts_only_quiescent_states(self):
        for state in ('idle', 'complete', 'aborted'):
            backend = Mock(token='synthetic-fixture-test-token')
            backend.status.return_value = {'ok': True, **factory.EXPECTED_IDENTITY,
                                           'state': state, 'runId': 'prior-run'}
            backend.load_script.return_value = {'ok': True}
            client = factory.ScopedClient(backend)
            client.load_script(SCRIPT)
            backend.load_script.assert_called_once_with(SCRIPT)
            self.assertEqual(client._run, RUN)

    def test_arm_and_start_require_fresh_owned_run_and_exact_state(self):
        for operation, required in (('arm', 'loaded'), ('start', 'armed')):
            for run in (RUN, 'foreign'):
                for state in ('idle', 'loaded', 'armed', 'running', 'complete', 'aborted', 'error', None):
                    client, backend = self.client()
                    backend.reset_mock()
                    backend.status.return_value = {'ok': True, **factory.EXPECTED_IDENTITY,
                                                   'state': state, 'runId': run}
                    method = getattr(client, operation)
                    args = (RUN,) if operation == 'arm' else (RUN, 500)
                    getattr(backend, operation).return_value = {'ok': True}
                    if run == RUN and state == required:
                        method(*args)
                        getattr(backend, operation).assert_called_once_with(*args)
                    else:
                        with self.assertRaises(RuntimeError): method(*args)
                        getattr(backend, operation).assert_not_called()
                    backend.status.assert_called_once_with()

    def test_status_failure_refuses_mutation_without_retry(self):
        client, backend = self.client()
        backend.reset_mock()
        backend.status.side_effect = RuntimeError('synthetic-sensitive-error')
        with self.assertRaises(RuntimeError): client.start(RUN, 500)
        backend.status.assert_called_once_with()
        backend.start.assert_not_called()

    def test_frozen_transport_endpoint_authority_and_inert_construction(self):
        class Base:
            def __init__(self, host, token, port, timeout):
                self.host, self.token, self.port, self.timeout = host, token, port, timeout
        module = types.SimpleNamespace(FixtureClient=Base)
        connection = Mock()
        response = connection.getresponse.return_value
        response.status = 200
        response.read.return_value = b'{}'
        with patch.object(factory.http.client, 'HTTPConnection', return_value=connection) as connect:
            backend = factory._transport(module, 'synthetic-fixture-test-token')
            connect.assert_not_called()
            backend.host = 'untrusted-change.local'
            self.assertEqual(backend.request('GET', '/v1/status', headers={'host': 'other'}), '{}')
            connect.assert_called_once_with('192.168.1.221', 8080, timeout=10.0)
            outgoing = connection.request.call_args.kwargs['headers']
            self.assertEqual(outgoing['Host'], 'keypath-hid-fixture.local:8080')
            self.assertNotIn('host', outgoing)
            self.assertEqual(outgoing['Connection'], 'close')
            connection.request.side_effect = OSError('synthetic-sensitive-error')
            with self.assertRaises(RuntimeError) as failure: backend.request('POST', '/v1/arm')
            self.assertNotIn('synthetic-sensitive-error', str(failure.exception))
            self.assertEqual(connection.request.call_count, 2)
            connection.close.assert_called_once_with()

    def test_missing_selected_credential_has_no_fallback(self):
        with patch.object(factory, '_module', return_value=types.SimpleNamespace()), \
             patch.object(factory, '_selected_token', side_effect=RuntimeError('synthetic-sensitive-error')), \
             self.assertRaises(RuntimeError) as failure:
            factory.create_client()
        self.assertNotIn('synthetic-sensitive-error', str(failure.exception))

    def test_failed_mutation_never_retries_or_reflects_exception(self):
        client, backend = self.client()
        backend.status.return_value = {'ok': True, **factory.EXPECTED_IDENTITY, 'state': 'armed', 'runId': RUN}
        backend.start.side_effect = RuntimeError(backend.token)
        with self.assertRaises(RuntimeError) as failure:
            client.start(RUN, 500)
        backend.start.assert_called_once_with(RUN, 500)
        self.assertNotIn(backend.token, str(failure.exception))

    def test_foreign_run_and_abort_are_refused_without_mutation(self):
        client, backend = self.client()
        with self.assertRaises(RuntimeError): client.arm('foreign')
        backend.arm.assert_not_called()
        backend.status.return_value = {'ok': True, **factory.EXPECTED_IDENTITY, 'runId': 'foreign', 'state': 'running'}
        with self.assertRaises(RuntimeError): client.abort()
        backend.abort.assert_not_called()

    def test_one_shot_trace_pages_with_zero_retry_window(self):
        client, backend = self.client()
        backend.request.side_effect = [f'{{"runId":"{RUN}","from":0,"available":2}}\n{{"sequence":1}}',
                                       f'{{"runId":"{RUN}","from":1,"available":2}}\n{{"sequence":2}}']
        self.assertEqual(client.trace_all(limit=1, retry_seconds=0), [{'sequence':1}, {'sequence':2}])
        self.assertEqual(backend.request.call_count, 2)
        backend.trace_all.assert_not_called()

    def test_trace_failure_and_reflection_never_retry(self):
        for response in (RuntimeError('synthetic-sensitive-error'), 'synthetic-fixture-test-token',
                         f'{{"runId":"foreign","from":0,"available":1}}\n{{"sequence":1}}'):
            client, backend = self.client()
            if isinstance(response, Exception): backend.request.side_effect = response
            else: backend.request.return_value = response
            with self.assertRaises(RuntimeError) as failure: client.trace_all(retry_seconds=0)
            backend.request.assert_called_once()
            self.assertNotIn('synthetic-sensitive-error', str(failure.exception))
            self.assertNotIn(backend.token, str(failure.exception))

    def test_close_scrubs_token_even_when_transport_close_fails(self):
        client, backend = self.client()
        backend.close.side_effect = RuntimeError(backend.token)
        with self.assertRaises(RuntimeError): client.close()
        self.assertEqual(backend.token, '')
        client.close()
        backend.close.assert_called_once()
        with self.assertRaises(RuntimeError): client.status()
        backend.status.assert_called_once_with()

    def test_escaped_unicode_nested_and_key_reflections_are_refused(self):
        for token in ('quoted"token', 'backslash\\token', 'unicode-雪-🔒'):
            for response in ({'value': token}, {'outer': [{'value': 'prefix-' + token + '-suffix'}]},
                             {token: 'safe'}, {'outer': [{token: 'safe'}]}, token):
                backend = Mock(token=token)
                backend.status.return_value = response
                client = factory.ScopedClient(backend)
                with self.assertRaises(RuntimeError) as failure:
                    client.status()
                backend.status.assert_called_once_with()
                self.assertNotIn(token, str(failure.exception))

    def test_escaped_ndjson_header_and_trace_extras_never_escape(self):
        for token in ('quoted"token', 'backslash\\token', 'unicode-雪-🔒'):
            for reflect_header in (True, False):
                client, backend = self.client()
                backend.token = token
                header = {'runId': RUN, 'from': 0, 'available': 1}
                row = {'sequence': 1}
                destination = header if reflect_header else row
                destination['extra'] = {'nested': [{token: 'prefix-' + token + '-suffix'}]}
                raw = json.dumps(header) + '\n' + json.dumps(row)
                self.assertNotIn(token, raw)
                backend.request.return_value = raw
                with self.assertRaises(RuntimeError) as failure:
                    client.trace_all(retry_seconds=0)
                backend.request.assert_called_once()
                self.assertNotIn(token, str(failure.exception))

    def test_bounded_response_walk_fails_closed_on_cycles_and_objects(self):
        cycle = []; cycle.append(cycle)
        deep = []
        for _ in range(34): deep = [deep]
        for response in (cycle, deep, object(), {1: 'safe'}, [None] * 4097,
                         {'value': 'x' * 1048577}, float('nan')):
            backend = Mock(token='synthetic-fixture-test-token')
            backend.status.return_value = response
            client = factory.ScopedClient(backend)
            with self.assertRaises(RuntimeError): client.status()
            backend.status.assert_called_once_with()

    def test_nested_nonreflecting_json_values_are_preserved(self):
        response = {'nested': [None, True, False, 17, 1.5, {'message': 'safe'}]}
        backend = Mock(token='synthetic-fixture-test-token')
        backend.status.return_value = response
        self.assertIs(factory.ScopedClient(backend).status(), response)

    def test_retry_and_oversized_trace_requests_are_rejected(self):
        client, backend = self.client()
        for options in ({'retry_seconds': 1}, {'limit': 9}):
            with self.assertRaises(RuntimeError): client.trace_all(**options)
        backend.request.assert_not_called()

if __name__ == '__main__': unittest.main()
