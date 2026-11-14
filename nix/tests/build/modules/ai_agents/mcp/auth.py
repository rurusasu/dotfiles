"""Exercise the real shared adapter and authenticated HTTP over a private socket."""

import asyncio
import contextlib
import http.server
import os
import secrets
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

import httpx
from mcp import ClientSession, StdioServerParameters, types
from mcp.client.stdio import stdio_client
from mcp.server import Server
from mcp.server.stdio import stdio_server


async def backend():
    server = Server("auth-fixture")

    @server.list_tools()
    async def tools():
        return [types.Tool(name="identity", inputSchema={"type": "object"})]

    @server.call_tool()
    async def call(name, arguments):
        return [types.TextContent(type="text", text=str(os.getpid()))]

    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())


async def identity(adapter, environment):
    parameters = StdioServerParameters(command=adapter, env=environment)
    with open(os.devnull, "w") as errors:
        async with stdio_client(parameters, errlog=errors) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                assert [tool.name for tool in (await session.list_tools()).tools] == [
                    "identity"
                ]
                result = await session.call_tool("identity", {})
                assert not result.isError
                return result.content[0].text


@contextlib.contextmanager
def running(command, client, headers):
    with subprocess.Popen(
        command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
    ) as process:
        try:
            deadline = time.monotonic() + 20
            while True:
                assert process.poll() is None, process.stderr.read().decode()
                try:
                    if client.get("/status", headers=headers).status_code == 200:
                        break
                except httpx.ConnectError:
                    pass
                assert time.monotonic() < deadline, "MCP server startup timed out"
                time.sleep(0.1)
            yield
        finally:
            process.terminate()
            process.wait(timeout=10)


def check(proxy, adapter, home):
    with tempfile.TemporaryDirectory() as directory:
        # Relocate the generated fixture adapter into the build's writable root.
        local_adapter = Path(directory) / "adapter"
        local_adapter.write_text(Path(adapter).read_text().replace(home, directory))
        local_adapter.chmod(0o700)
        check_local(proxy, str(local_adapter), Path(directory) / ".local/state/mcp")


def check_local(proxy, adapter, directory):
    directory = Path(directory)
    directory.mkdir(parents=True, mode=0o700)
    token_file = directory / "shared-token"
    token_file.write_text(secrets.token_hex(32))
    token_file.chmod(0o600)
    socket_file = directory / "chrome.sock"
    headers = {"Authorization": f"Bearer {token_file.read_text()}"}
    received = []

    class ForeignEndpoint(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            received.append(self.headers.get("Authorization"))
            self.send_error(503)

        def log_message(self, *args):
            pass

    # A foreign endpoint also serves as a hostile inherited HTTP proxy.
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), ForeignEndpoint) as foreign:
        thread = threading.Thread(target=foreign.serve_forever, daemon=True)
        thread.start()
        address = f"http://127.0.0.1:{foreign.server_port}"
        environment = dict(
            os.environ,
            HTTP_PROXY=address,
            HTTPS_PROXY=address,
            ALL_PROXY=address,
            NO_PROXY="",
            no_proxy="",
        )
        command = [
            proxy,
            "--host",
            "127.0.0.1",
            "--port",
            "8765",
            "--log-level",
            "ERROR",
            "--auth-token-file",
            str(token_file),
            "--unix-socket",
            str(socket_file),
            "--",
            sys.executable,
            __file__,
            "--backend",
        ]
        with httpx.Client(
            transport=httpx.HTTPTransport(uds=str(socket_file)),
            base_url="http://127.0.0.1:8765",
            trust_env=False,
        ) as client:
            with running(command, client, headers):
                for path in ("/status", "/mcp", "/sse", "/messages/"):
                    assert client.get(path).status_code == 401
                assert (
                    client.get(
                        "/status", headers={"Authorization": "Bearer wrong"}
                    ).status_code
                    == 401
                )
                for key, value in (
                    ("Host", "attacker.invalid"),
                    ("Origin", "https://attacker.invalid"),
                ):
                    assert (
                        client.get(
                            "/status", headers=headers | {key: value}
                        ).status_code
                        == 403
                    )
                assert (
                    client.get("/status", headers=list(headers.items()) * 2).status_code
                    == 401
                )
                first = asyncio.run(identity(adapter, environment))
                assert asyncio.run(identity(adapter, environment)) == first

            # With the legitimate service absent, the adapter must not use TCP/proxy fallback.
            result = subprocess.run(
                [adapter],
                input=b"",
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=15,
            )
            assert result.returncode != 0
            assert received == [], "Adapter contacted a foreign HTTP endpoint"
            with running(command, client, headers):
                assert asyncio.run(identity(adapter, environment)) != first
            assert received == []

        directory.chmod(0o777)
        result = subprocess.run(
            [adapter],
            input=b"",
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode != 0
        assert (
            subprocess.run(
                command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=15
            ).returncode
            != 0
        )
        directory.chmod(0o700)
        token_file.chmod(0o644)
        assert (
            subprocess.run(
                command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=15
            ).returncode
            != 0
        )
        token_file.chmod(0o600)
        symlink = directory / "token-link"
        symlink.symlink_to(token_file)
        command[command.index(str(token_file))] = str(symlink)
        assert (
            subprocess.run(
                command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=15
            ).returncode
            != 0
        )
        assert received == []
        foreign.shutdown()
        thread.join(timeout=5)
    print(
        "Private socket adapters, authentication, shared backend and outage/restart passed"
    )


if __name__ == "__main__":
    if sys.argv[1] == "--backend":
        asyncio.run(backend())
    else:
        check(*sys.argv[1:])
