"""Redacted GitHub API credential validation for Hermes bootstrap."""

from __future__ import annotations

import json
import re
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

from .errors import CredentialError, RepositoryError
from .payload import SecretRedactor


_MAX_RESPONSE_BYTES = 1024 * 1024
_TIMEOUT_SECONDS = 10.0
_COMPONENT = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]*\Z")


@dataclass(frozen=True, repr=False)
class GitAuth:
    """GitHub authentication retained only for the current bootstrap process."""

    token: str
    redactor: SecretRedactor

    def __repr__(self) -> str:
        return "GitAuth(<redacted>)"


@dataclass(frozen=True)
class _Failure:
    error_type: type[CredentialError] | type[RepositoryError]
    message: str


class GitHubClient:
    """Minimal, bounded GitHub REST client with a sanitized error boundary."""

    def __init__(
        self,
        auth: GitAuth,
        *,
        opener: Callable[..., Any] = urlopen,
        api_base: str = "https://api.github.com",
        timeout: float = _TIMEOUT_SECONDS,
    ) -> None:
        self._auth = auth
        self._opener = opener
        self._api_base = _validated_api_base(api_base)
        self._timeout = timeout if isinstance(timeout, (int, float)) and timeout > 0 else _TIMEOUT_SECONDS

    def authenticated_login(self) -> str:
        """Return the authenticated GitHub login or raise a safe credential error."""

        result = self._authenticated_login_boundary()
        if isinstance(result, _Failure):
            error_type = result.error_type
            message = result.message
            del result
            del self
            raise error_type(message)
        return result

    def assert_repository_access(self, owner: str, repo: str) -> None:
        """Require readable access to exactly ``owner/repo``."""

        result = self._repository_access_boundary(owner, repo)
        if isinstance(result, _Failure):
            error_type = result.error_type
            message = result.message
            del result
            del owner
            del repo
            del self
            raise error_type(message)

    def _authenticated_login_boundary(self) -> str | _Failure:
        if not _valid_auth(self._auth):
            return _Failure(CredentialError, "GitHub credentials were rejected")
        payload = self._request_json("/user", CredentialError, "GitHub credentials were rejected")
        if isinstance(payload, _Failure):
            return payload
        login = payload.get("login")
        if not isinstance(login, str) or not login:
            return _Failure(CredentialError, "GitHub credentials were rejected")
        return login

    def _repository_access_boundary(self, owner: str, repo: str) -> None | _Failure:
        if not _valid_auth(self._auth):
            return _Failure(RepositoryError, "GitHub repository access was denied")
        if not _valid_component(owner) or not _valid_component(repo):
            return _Failure(RepositoryError, "GitHub repository access was denied")
        payload = self._request_json(
            f"/repos/{owner}/{repo}", RepositoryError, "GitHub repository access was denied"
        )
        if isinstance(payload, _Failure):
            return payload
        full_name = payload.get("full_name")
        if not isinstance(full_name, str) or full_name.casefold() != f"{owner}/{repo}".casefold():
            return _Failure(RepositoryError, "GitHub repository access was denied")
        permissions = payload.get("permissions")
        if permissions is not None and (
            not isinstance(permissions, Mapping) or permissions.get("pull") is not True
        ):
            return _Failure(RepositoryError, "GitHub repository access was denied")
        return None

    def _request_json(
        self,
        endpoint: str,
        error_type: type[CredentialError] | type[RepositoryError],
        message: str,
    ) -> Mapping[str, object] | _Failure:
        """Keep request, body, and opener exceptions inside this non-raising boundary."""

        try:
            request = Request(
                f"{self._api_base}{endpoint}",
                headers={
                    "Authorization": f"Bearer {self._auth.token}",
                    "Accept": "application/vnd.github+json",
                    "X-GitHub-Api-Version": "2022-11-28",
                },
            )
            response = self._opener(request, timeout=self._timeout)
            try:
                status = _response_status(response)
                final_url = response.geturl()
                body = response.read(_MAX_RESPONSE_BYTES + 1)
            finally:
                _close_response(response)
            if status < 200 or status >= 300 or not _same_origin(final_url, self._api_base):
                return _Failure(error_type, message)
            if not isinstance(body, bytes) or len(body) > _MAX_RESPONSE_BYTES:
                return _Failure(error_type, message)
            decoded = body.decode("utf-8")
            payload = json.loads(decoded)
            if not isinstance(payload, Mapping):
                return _Failure(error_type, message)
            return dict(payload)
        except HTTPError as error:
            _close_response(error)
            return _Failure(error_type, message)
        except (URLError, OSError, UnicodeError, ValueError, TypeError, json.JSONDecodeError):
            return _Failure(error_type, message)
        except Exception:
            return _Failure(error_type, message)


def _validated_api_base(value: str) -> str:
    parsed = urlsplit(value)
    if (
        parsed.scheme not in {"http", "https"}
        or not parsed.netloc
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        return "https://api.github.com"
    return value.rstrip("/")


def _response_status(response: object) -> int:
    status = getattr(response, "status", None)
    if isinstance(status, int):
        return status
    getcode = getattr(response, "getcode", None)
    status = getcode() if callable(getcode) else None
    if not isinstance(status, int):
        raise ValueError("invalid response status")
    return status


def _close_response(response: object) -> None:
    close = getattr(response, "close", None)
    if callable(close):
        try:
            close()
        except Exception:
            pass


def _same_origin(url: object, expected_base: str) -> bool:
    if not isinstance(url, str):
        return False
    actual = urlsplit(url)
    expected = urlsplit(expected_base)
    return actual.scheme == expected.scheme and actual.netloc.casefold() == expected.netloc.casefold()


def _valid_component(value: object) -> bool:
    return isinstance(value, str) and _COMPONENT.fullmatch(value) is not None


def _valid_auth(auth: object) -> bool:
    return (
        isinstance(auth, GitAuth)
        and isinstance(auth.token, str)
        and bool(auth.token)
        and auth.token == auth.token.strip()
        and isinstance(auth.redactor, SecretRedactor)
    )
