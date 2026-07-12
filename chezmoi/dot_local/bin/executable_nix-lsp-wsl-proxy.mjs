#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawn } from "node:child_process";

const defaultDistro = "NixOS";
const defaultUser = "nixos";

function windowsUriToWslUri(value) {
  return value.replace(/^file:\/\/\/([A-Za-z]):(\/.*)$/u, (_, drive, rest) => {
    return `file:///mnt/${drive.toLowerCase()}${rest.replaceAll("\\", "/")}`;
  });
}

function wslUriToWindowsUri(value) {
  return value.replace(/^file:\/\/\/mnt\/([A-Za-z])(\/.*)$/u, (_, drive, rest) => {
    return `file:///${drive.toUpperCase()}:${rest}`;
  });
}

function windowsPathToWslPath(value) {
  if (value.includes("\n")) {
    return value;
  }

  return value.replace(/^([A-Za-z]):[\\/](.*)$/u, (_, drive, rest) => {
    return `/mnt/${drive.toLowerCase()}/${rest.replaceAll("\\", "/")}`;
  });
}

function wslPathToWindowsPath(value) {
  if (value.includes("\n")) {
    return value;
  }

  return value.replace(/^\/mnt\/([A-Za-z])\/(.*)$/u, (_, drive, rest) => {
    return `${drive.toUpperCase()}:\\${rest.replaceAll("/", "\\")}`;
  });
}

function translateClientString(value) {
  return windowsPathToWslPath(windowsUriToWslUri(value));
}

function translateServerString(value) {
  return wslPathToWindowsPath(wslUriToWindowsUri(value));
}

function translateJson(value, translateString) {
  if (typeof value === "string") {
    return translateString(value);
  }

  if (Array.isArray(value)) {
    return value.map((item) => translateJson(item, translateString));
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, translateJson(item, translateString)])
    );
  }

  return value;
}

function findHeaderEnd(buffer) {
  const crlf = buffer.indexOf("\r\n\r\n");
  if (crlf >= 0) {
    return { index: crlf, length: 4 };
  }

  const lf = buffer.indexOf("\n\n");
  if (lf >= 0) {
    return { index: lf, length: 2 };
  }

  return null;
}

function createFrameParser(onFrame) {
  let buffer = Buffer.alloc(0);

  return (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);

    while (true) {
      const headerEnd = findHeaderEnd(buffer);
      if (!headerEnd) {
        return;
      }

      const header = buffer.subarray(0, headerEnd.index).toString("ascii");
      const match = header.match(/(?:^|\r?\n)Content-Length:\s*(\d+)/iu);
      if (!match) {
        throw new Error("LSP frame is missing Content-Length");
      }

      const bodyLength = Number.parseInt(match[1], 10);
      const bodyStart = headerEnd.index + headerEnd.length;
      const frameLength = bodyStart + bodyLength;
      if (buffer.length < frameLength) {
        return;
      }

      const raw = buffer.subarray(0, frameLength);
      const body = buffer.subarray(bodyStart, frameLength);
      buffer = buffer.subarray(frameLength);
      onFrame({ raw, body });
    }
  };
}

function writeFrame(output, message) {
  const body = Buffer.from(JSON.stringify(message), "utf8");
  output.write(`Content-Length: ${body.length}\r\n\r\n`);
  output.write(body);
}

function forwardFrame(frame, output, translateString) {
  try {
    const message = JSON.parse(frame.body.toString("utf8"));
    writeFrame(output, translateJson(message, translateString));
  } catch (error) {
    process.stderr.write(`[nix-lsp-wsl-proxy] forwarding unmodified frame: ${error.message}\n`);
    output.write(frame.raw);
  }
}

function backendRelaySource() {
  return [
    'const { spawn } = require("node:child_process");',
    "const [nixd, ...args] = process.argv.slice(1);",
    'const server = spawn(nixd, args, { stdio: ["pipe", "pipe", "pipe"] });',
    "process.stdin.pipe(server.stdin);",
    "server.stdout.pipe(process.stdout);",
    "server.stderr.pipe(process.stderr);",
    'server.on("error", (error) => { console.error(`[nix-lsp-wsl-proxy] failed to start nixd: ${error.message}`); process.exitCode = 1; });',
    'server.on("exit", (code, signal) => process.exit(code ?? (signal ? 1 : 0)));',
    'for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => server.kill(signal));',
  ].join("");
}

function runSelfTest() {
  assert.equal(
    windowsUriToWslUri("file:///D:/ruru/dotfiles/flake.nix"),
    "file:///mnt/d/ruru/dotfiles/flake.nix"
  );
  assert.equal(
    windowsUriToWslUri("file:///C:/Users/Kohei%20Miki/test.nix"),
    "file:///mnt/c/Users/Kohei%20Miki/test.nix"
  );
  assert.equal(windowsPathToWslPath("D:\\ruru\\dotfiles"), "/mnt/d/ruru/dotfiles");
  assert.equal(
    wslUriToWindowsUri("file:///mnt/d/ruru/dotfiles/flake.nix"),
    "file:///D:/ruru/dotfiles/flake.nix"
  );
  assert.equal(wslPathToWindowsPath("/mnt/d/ruru/dotfiles"), "D:\\ruru\\dotfiles");
  assert.deepEqual(
    translateJson(
      {
        params: {
          rootUri: "file:///D:/ruru/dotfiles",
          rootPath: "D:\\ruru\\dotfiles",
          text: "{ config, ... }:",
        },
      },
      translateClientString
    ),
    {
      params: {
        rootUri: "file:///mnt/d/ruru/dotfiles",
        rootPath: "/mnt/d/ruru/dotfiles",
        text: "{ config, ... }:",
      },
    }
  );
  console.log("ok");
}

function main() {
  const args = process.argv.slice(2);
  if (args.includes("--self-test")) {
    runSelfTest();
    return;
  }

  const distro = process.env.DOTFILES_NIX_LSP_WSL_DISTRO || defaultDistro;
  const user = process.env.DOTFILES_NIX_LSP_WSL_USER || defaultUser;
  const nixd = process.env.DOTFILES_NIX_LSP_WSL_NIXD || `/etc/profiles/per-user/${user}/bin/nixd`;
  const relay = backendRelaySource();
  const server = spawn(
    "wsl.exe",
    [
      "--distribution",
      distro,
      "--user",
      user,
      "--exec",
      "sh",
      "-lc",
      'exec node -e "$0" "$@"',
      relay,
      nixd,
      ...args,
    ],
    {
      stdio: ["pipe", "pipe", "pipe"],
    }
  );

  server.on("error", (error) => {
    process.stderr.write(`[nix-lsp-wsl-proxy] failed to start WSL nixd: ${error.message}\n`);
    process.exitCode = 1;
  });

  server.on("exit", (code, signal) => {
    process.exitCode = code ?? (signal ? 1 : 0);
  });

  server.stderr.pipe(process.stderr);

  const clientToServer = createFrameParser((frame) => {
    forwardFrame(frame, server.stdin, translateClientString);
  });
  const serverToClient = createFrameParser((frame) => {
    forwardFrame(frame, process.stdout, translateServerString);
  });

  process.stdin.on("data", clientToServer);
  process.stdin.on("end", () => server.stdin.end());
  server.stdout.on("data", serverToClient);

  for (const signal of ["SIGINT", "SIGTERM"]) {
    process.on(signal, () => {
      server.kill(signal);
    });
  }
}

main();
