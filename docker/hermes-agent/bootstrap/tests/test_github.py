from __future__ import annotations

import io
import json
import sys
import unittest
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
