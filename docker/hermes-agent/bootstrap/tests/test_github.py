from __future__ import annotations

import io
import json
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import FrameType, TracebackType
from urllib.error import HTTPError
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import CredentialError, RepositoryError
from hermes_bootstrap.github import GitAuth, GitHubClient
from hermes_bootstrap.payload import SecretRedactor


class FakeResponse:
    def __init__(self, body: bytes, *, status: int = 200, url: str = "https://api.github.test/user") -> None:
        self._body = body
        self.status = status
        self._url = url

    def read(self, size: int = -1) -> bytes:
        return self._body if size < 0 else self._body[:size]

    def getcode(self) -> int:
        return self.status

    def geturl(self) -> str:
        return self._url

    def close(self) -> None:
        return None


class LocalHTTPServer:
    def __init__(self, handler: type[BaseHTTPRequestHandler]) -> None:
        self._server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self._server.daemon_threads = True
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()

    @property
    def base_url(self) -> str:
        host, port = self._server.server_address[:2]
        return f"http://{host}:{port}"

    def close(self) -> None:
        self._server.shutdown()
        self._server.server_close()
        self._thread.join(timeout=2)


def auth() -> GitAuth:
    token = "github-token-marker"
    return GitAuth(token=token, redactor=SecretRedactor((token,)))


def capture_error(callback: object) -> BaseException:
    try:
        callback()
    except (CredentialError, RepositoryError) as error:
        return error
    raise AssertionError("expected GitHub validation to fail")


class GitHubClientTests(unittest.TestCase):
    def assert_hidden(self, error: BaseException, *markers: str) -> None:
        pending: list[object] = [error]
        visited: set[int] = set()
        while pending:
            value = pending.pop()
            if id(value) in visited:
                continue
            visited.add(id(value))
            if isinstance(value, str):
                for marker in markers:
                    self.assertNotIn(marker, value)
            elif isinstance(value, bytes):
                for marker in markers:
                    self.assertNotIn(marker.encode(), value)
            elif isinstance(value, BaseException):
                pending.extend((value.__cause__, value.__context__, value.__traceback__, value.args))
            elif isinstance(value, TracebackType):
                pending.extend((value.tb_frame, value.tb_next))
            elif isinstance(value, FrameType):
                pending.extend(value.f_locals.values())
            elif isinstance(value, dict):
                pending.extend((*value.keys(), *value.values()))
            elif isinstance(value, (list, tuple, set, frozenset)):
                pending.extend(value)

    def test_authenticated_login_sends_fixed_headers_and_returns_login(self) -> None:
        calls: list[object] = []

        def opener(request: object, *, timeout: float) -> FakeResponse:
            calls.append((request, timeout))
            return FakeResponse(b'{"login":"octocat"}')

        client = GitHubClient(auth(), opener=opener, api_base="https://api.github.test")
        self.assertEqual(client.authenticated_login(), "octocat")
        request, timeout = calls[0]
        self.assertEqual(request.full_url, "https://api.github.test/user")
        self.assertEqual(request.get_header("Authorization"), "Bearer github-token-marker")
        self.assertEqual(request.get_header("Accept"), "application/vnd.github+json")
        self.assertEqual(request.get_header("X-github-api-version"), "2022-11-28")
        self.assertGreater(timeout, 0)

    def test_invalid_credentials_and_response_data_are_redacted_from_exception_graph(self) -> None:
        marker = "github-response-marker"

        def opener(request: object, *, timeout: float) -> object:
            raise HTTPError(request.full_url, 401, f"Bearer github-token-marker {marker}", {}, io.BytesIO(marker.encode()))

        error = capture_error(lambda: GitHubClient(auth(), opener=opener).authenticated_login())
        self.assertIsInstance(error, CredentialError)
        self.assertIsNone(error.__cause__)
        self.assertIsNone(error.__context__)
        self.assert_hidden(error, "github-token-marker", marker)

    def test_default_opener_rejects_cross_origin_redirect_before_sending_authorization(self) -> None:
        target_requests: list[str | None] = []

        class TargetHandler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802
                target_requests.append(self.headers.get("Authorization"))
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'{"login":"attacker"}')

            def log_message(self, _format: str, *_args: object) -> None:
                return None

        target = LocalHTTPServer(TargetHandler)
        self.addCleanup(target.close)
        origin_requests: list[str | None] = []

        class OriginHandler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802
                origin_requests.append(self.headers.get("Authorization"))
                self.send_response(302)
                self.send_header("Location", f"{target.base_url}/user")
                self.end_headers()

            def log_message(self, _format: str, *_args: object) -> None:
                return None

        origin = LocalHTTPServer(OriginHandler)
        self.addCleanup(origin.close)

        error = capture_error(lambda: GitHubClient(auth(), api_base=origin.base_url).authenticated_login())

        self.assertIsInstance(error, CredentialError)
        self.assertIsNone(error.__cause__)
        self.assertIsNone(error.__context__)
        self.assert_hidden(error, "github-token-marker")
        self.assertEqual(origin_requests, ["Bearer github-token-marker"])
        self.assertEqual(target_requests, [])

    def test_default_opener_accepts_same_origin_redirect(self) -> None:
        requests: list[tuple[str, str | None]] = []

        class OriginHandler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802
                requests.append((self.path, self.headers.get("Authorization")))
                if self.path == "/user":
                    self.send_response(302)
                    self.send_header("Location", "/redirected-user")
                    self.end_headers()
                    return
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'{"login":"octocat"}')

            def log_message(self, _format: str, *_args: object) -> None:
                return None

        origin = LocalHTTPServer(OriginHandler)
        self.addCleanup(origin.close)

        self.assertEqual(GitHubClient(auth(), api_base=origin.base_url).authenticated_login(), "octocat")
        self.assertEqual(
            requests,
            [
                ("/user", "Bearer github-token-marker"),
                ("/redirected-user", "Bearer github-token-marker"),
            ],
        )

    def test_rejects_redirect_malformed_and_oversized_user_responses(self) -> None:
        cases = (
            FakeResponse(b'{"login":"octocat"}', url="https://elsewhere.test/user"),
            FakeResponse(b"not-json"),
            FakeResponse(b"x" * (1024 * 1024 + 1)),
            FakeResponse(b"[]"),
            FakeResponse(b'{"login":""}'),
        )
        for response in cases:
            with self.subTest(response=response._url):
                error = capture_error(
                    lambda response=response: GitHubClient(auth(), opener=lambda _request, *, timeout: response).authenticated_login()
                )
                self.assertIsInstance(error, CredentialError)

    def test_repository_access_requires_identity_and_pull_permission(self) -> None:
        responses = iter(
            (
                FakeResponse(b'{"full_name":"Acme/Widget","permissions":{"pull":true}}', url="https://api.github.test/repos/acme/widget"),
                FakeResponse(b'{"full_name":"acme/other","permissions":{"pull":true}}', url="https://api.github.test/repos/acme/widget"),
                FakeResponse(b'{"full_name":"acme/widget","permissions":{"pull":false}}', url="https://api.github.test/repos/acme/widget"),
            )
        )
        client = GitHubClient(auth(), opener=lambda _request, *, timeout: next(responses), api_base="https://api.github.test")
        client.assert_repository_access("acme", "widget")
        with self.assertRaises(RepositoryError):
            client.assert_repository_access("acme", "widget")
        with self.assertRaises(RepositoryError):
            client.assert_repository_access("acme", "widget")

    def test_invalid_repository_components_do_not_reach_http(self) -> None:
        opener = mock.Mock()
        client = GitHubClient(auth(), opener=opener)
        for owner, repository in (("", "repo"), ("acme/evil", "repo"), ("acme", "repo?x=1")):
            with self.subTest(owner=owner, repository=repository):
                with self.assertRaises(RepositoryError):
                    client.assert_repository_access(owner, repository)
        opener.assert_not_called()

    def test_empty_or_invalid_auth_fails_before_http(self) -> None:
        opener = mock.Mock()
        invalid = GitAuth(token="", redactor=SecretRedactor(()))
        with self.assertRaises(CredentialError):
            GitHubClient(invalid, opener=opener).authenticated_login()
        with self.assertRaises(RepositoryError):
            GitHubClient(invalid, opener=opener).assert_repository_access("acme", "widget")
        opener.assert_not_called()
