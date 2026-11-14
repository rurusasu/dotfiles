"""Protect the complete shared MCP HTTP application with a local bearer token."""

import hmac
import os
import re
import stat
import sys
from pathlib import Path

from starlette.responses import PlainTextResponse


def private_socket_path(path: str) -> str:
    """Resolve the endpoint beneath a private directory no other UID can replace."""
    socket = Path(path)
    directory = socket.parent.resolve(strict=True)
    owner = os.getuid()
    for ancestor in (directory, *directory.parents):
        # The namespace root is the OS trust boundary (also in rootless sandboxes).
        if ancestor == ancestor.parent:
            continue
        info = ancestor.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid not in (0, owner):
            raise ValueError(
                f"MCP socket ancestor {ancestor} has an untrusted owner (uid={info.st_uid})"
            )
        if info.st_mode & 0o022 and not info.st_mode & stat.S_ISVTX:
            raise ValueError(
                "MCP socket ancestors must not allow untrusted replacement"
            )
    info = directory.lstat()
    if info.st_uid != owner or info.st_mode & 0o077:
        raise ValueError(
            "MCP socket directory must be owned by this user with mode 0700"
        )
    resolved = directory / socket.name
    if len(os.fsencode(resolved)) > (103 if sys.platform == "darwin" else 107):
        raise ValueError("MCP Unix socket path exceeds the platform pathname limit")
    if resolved.exists() or resolved.is_symlink():
        info = resolved.lstat()
        if not stat.S_ISSOCK(info.st_mode) or info.st_uid != owner:
            raise ValueError("MCP endpoint must be a Unix socket owned by this user")
    return str(resolved)


def read_token(token_file: str) -> bytes:
    with os.fdopen(os.open(token_file, os.O_RDONLY | os.O_NOFOLLOW), "rb") as stream:
        metadata = os.fstat(stream.fileno())
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != os.getuid()
            or stat.S_IMODE(metadata.st_mode) & 0o077
        ):
            raise ValueError("MCP token must be a private file owned by this user")
        token = stream.read(66)
    if not re.fullmatch(rb"[0-9a-f]{64}\n?", token):
        raise ValueError("MCP token must contain 32 random bytes encoded as hex")
    return token.rstrip(b"\n")


class LocalBearerAuth:
    def __init__(self, app, *, token: bytes, host: str):
        self.app = app
        self.host = host.encode("ascii")
        self.authorization = b"Bearer " + token

    async def __call__(self, scope, receive, send):
        if scope["type"] == "lifespan":
            await self.app(scope, receive, send)
            return
        if scope["type"] != "http":
            await send({"type": "websocket.close", "code": 1008})
            return

        headers = scope["headers"]
        hosts = [value for name, value in headers if name == b"host"]
        origins = [value for name, value in headers if name == b"origin"]
        if hosts != [self.host] or (origins and origins != [b"http://" + self.host]):
            await PlainTextResponse("Forbidden", status_code=403)(scope, receive, send)
            return
        credentials = [value for name, value in headers if name == b"authorization"]
        if len(credentials) != 1 or not hmac.compare_digest(
            credentials[0], self.authorization
        ):
            await PlainTextResponse(
                "Unauthorized", status_code=401, headers={"WWW-Authenticate": "Bearer"}
            )(scope, receive, send)
            return
        await self.app(scope, receive, send)
