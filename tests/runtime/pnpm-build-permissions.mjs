// Characterize persisted pnpm approvals and exercise the shipped install arguments.
// The local registry serves only a harmless fixture; no real node-pty is downloaded.
import assert from "node:assert/strict";
import { spawn, execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, rmSync } from "node:fs";
import http from "node:http";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repo = fileURLToPath(new URL("../../", import.meta.url));
const pnpm = process.env.PNPM_TEST_EXECUTABLE || "pnpm";
const root = mkdtempSync(path.join(tmpdir(), "dotfiles-pnpm-permissions-"));
const fixtureDir = path.join(repo, "tests/fixtures/pnpm-build-permissions");
const catalog = JSON.parse(readFileSync(path.join(repo, "windows/pnpm/packages.json"), "utf8"));
const fixtureManifest = JSON.parse(
  readFileSync(path.join(fixtureDir, "package/package.json"), "utf8")
);
const tarball = path.join(root, "node-pty.tgz");
const server = http.createServer();
const env = Object.fromEntries(
  Object.entries(process.env).filter(([key]) => !/^(pnpm_|npm_config_|path$)/i.test(key))
);
const dirs = Object.fromEntries(
  ["home", "store", "cache", "state", "config"].map((key) => [key, path.join(root, key)])
);
const bin = path.join(dirs.home, "bin");
Object.values(dirs)
  .concat(bin)
  .forEach((dir) => mkdirSync(dir, { recursive: true }));
Object.assign(env, {
  PNPM_HOME: dirs.home,
  CI: "true",
  PATH: bin + path.delimiter + process.env.PATH,
});

async function run(label, flags, expectedBuild, permission, approveOnly = false) {
  const command = approveOnly
    ? ["approve-builds", "-g"]
    : ["add", "-g", "node-pty@0.0.1", "--force", "--no-side-effects-cache"];
  const args = [
    ...command,
    "--reporter=append-only",
    "--yes",
    `--registry=http://127.0.0.1:${server.address().port}`,
    `--store-dir=${dirs.store}`,
    `--state-dir=${dirs.state}`,
    `--config.cache-dir=${dirs.cache}`,
    `--config.config-dir=${dirs.config}`,
    ...flags,
  ];
  const output = await new Promise((resolve, reject) => {
    const child = spawn(pnpm, args, { cwd: root, env, windowsHide: true });
    let out = "";
    child.stdout.on("data", (data) => (out += data));
    child.stderr.on("data", (data) => (out += data));
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error(`${label} timed out\n${out}`));
    }, 45000);
    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      code === 0 ? resolve(out) : reject(new Error(`${label}: exit ${code}\n${out}`));
    });
  });
  const saved = readFileSync(path.join(dirs.home, "global/v11/pnpm-workspace.yaml"), "utf8");
  assert.equal(
    output.includes("BUILD_PERMISSION_PROBE_EXECUTED"),
    expectedBuild,
    `${label}\n${output}`
  );
  assert.equal(saved.match(/node-pty:\s*(true|false)/)?.[1], permission, saved);
  assert.match(saved, /['"]?@github\/keytar['"]?:\s*true/, "Unrelated approval must be preserved");
  console.log(`PASS ${label}: build=${expectedBuild}, saved permission=${permission}`);
}

try {
  const version = execFileSync(pnpm, ["--version"], {
    cwd: root,
    env,
    encoding: "utf8",
    timeout: 45000,
  }).trim();
  assert.match(version, /^12\./, "This regression exercises pnpm 12's global layout and deny flag");
  console.log(`Testing pnpm ${version}`);
  execFileSync("tar", ["-czf", tarball, "-C", fixtureDir, "package"], { timeout: 10000 });
  const fixture = readFileSync(tarball);
  const shasum = createHash("sha1").update(fixture).digest("hex");
  server.on("request", (req, res) => {
    if (req.url === "/node-pty") {
      res.setHeader("Content-Type", "application/json");
      res.end(
        JSON.stringify({
          name: "node-pty",
          "dist-tags": { latest: "0.0.1" },
          versions: {
            "0.0.1": {
              ...fixtureManifest,
              dist: { tarball: `http://127.0.0.1:${server.address().port}/node-pty.tgz`, shasum },
            },
          },
        })
      );
    } else if (req.url === "/node-pty.tgz") {
      res.end(fixture);
    } else {
      res.writeHead(404);
      res.end("Not found");
    }
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  await run(
    "old approval",
    ["--allow-build=node-pty", "--allow-build=@github/keytar"],
    true,
    "true"
  );
  await run("omitting approval does not revoke it", [], true, "true");
  const permissionPath = path.join(dirs.home, "global/v11/pnpm-workspace.yaml");
  const oldApprovals = readFileSync(permissionPath, "utf8");
  await run("pre-skip migration without pending packages", ["!node-pty"], false, "false", true);
  await run("pre-skip migration is idempotent", ["!node-pty"], false, "false", true);
  await run("pre-skip denial persists", [], false, "false");
  for (const name of ["@deepseek-ai/dsh", "@google/gemini-cli"]) {
    // Each package must independently migrate true -> false, not rely on its predecessor.
    writeFileSync(permissionPath, oldApprovals);
    const entry = catalog.globalPackages.find((pkg) => pkg.name === name);
    assert.ok(entry, `${name} must be present in the shipped manifest`);
    await run(`${name} revokes saved approval`, entry.installArgs || [], false, "false");
    await run(`${name} remains safe on repeat`, entry.installArgs || [], false, "false");
  }
  await run("denial persists without flags", [], false, "false");
} finally {
  if (server.listening) await new Promise((resolve) => server.close(resolve));
  // Only remove the fresh directory this test created, never PNPM_HOME from the caller.
  assert.equal(path.dirname(root), path.resolve(tmpdir()));
  assert.ok(path.basename(root).startsWith("dotfiles-pnpm-permissions-"));
  rmSync(root, { recursive: true, force: true });
}
