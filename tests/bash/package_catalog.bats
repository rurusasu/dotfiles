#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	SETS="$REPO_ROOT/nix/packages/sets.nix"
}

nix_fixture_errors() {
	run --separate-stderr nix eval --impure --json --expr "
		let
			flake = builtins.getFlake (toString $REPO_ROOT);
			pkgs = import flake.inputs.nixpkgs { system = \"aarch64-darwin\"; config.allowUnfree = true; };
			lib = flake.inputs.nixpkgs.lib;
			sets = import $SETS { inherit pkgs lib; catalogOverride = $1; };
		in sets.providerErrors
	"
}

nix_fixture_darwin_package_split() {
	run --separate-stderr nix eval --impure --json --expr "
		let
			flake = builtins.getFlake (toString $REPO_ROOT);
			pkgs = import flake.inputs.nixpkgs { system = \"aarch64-darwin\"; config.allowUnfree = true; };
			lib = flake.inputs.nixpkgs.lib;
			sets = import $SETS {
				inherit pkgs lib;
				catalogOverride = {
					gui = {
						pkg = pkgs.hello;
						category = \"test\";
						installFeature = \"WithGui\";
						support.darwin = {
							provider = \"nix\";
							source = \"nixpkgs\";
							nixAttr = \"hello\";
							identity.appName = \"Test App.app\";
						};
					};
					command = {
						pkg = pkgs.cowsay;
						category = \"test\";
						support.darwin = {
							provider = \"nix\";
							source = \"nixpkgs\";
							nixAttr = \"cowsay\";
							identity = \"cowsay\";
						};
					};
				};
			};
			contains = package: packages: builtins.elem package packages;
			defaultSystem = sets.darwinSystemPackagesForInstallFeatures [ ];
			defaultHome = sets.darwinHomePackagesForInstallFeatures [ ];
			enabledSystem = sets.darwinSystemPackagesForInstallFeatures [ \"WithGui\" ];
			enabledHome = sets.darwinHomePackagesForInstallFeatures [ \"WithGui\" ];
		in {
			default = {
				guiSystem = contains pkgs.hello defaultSystem;
				guiHome = contains pkgs.hello defaultHome;
				commandSystem = contains pkgs.cowsay defaultSystem;
				commandHome = contains pkgs.cowsay defaultHome;
			};
			enabled = {
				guiSystem = contains pkgs.hello enabledSystem;
				guiHome = contains pkgs.hello enabledHome;
				commandSystem = contains pkgs.cowsay enabledSystem;
				commandHome = contains pkgs.cowsay enabledHome;
			};
		}
	"
}

@test "Claude and TablePlus are not managed by dotfiles" {
	! grep -Eqi 'claude|tableplus' "$SETS"
	! grep -Eqi 'Anthropic\.Claude|TablePlus\.TablePlus' "$REPO_ROOT/windows/winget/packages.json"
	! grep -Eqi 'claude-agent-acp' "$REPO_ROOT/windows/pnpm/packages.json"
	[ -z "$(find "$REPO_ROOT/chezmoi/dot_claude" -type f -print 2>/dev/null)" ]
	[ -z "$(find "$REPO_ROOT/chezmoi/AppData/Roaming/Claude" -type f -print 2>/dev/null)" ]
	[ ! -e "$REPO_ROOT/scripts/powershell/handlers/Handler.ClaudeCode.ps1" ]
	[ -e "$REPO_ROOT/chezmoi/dot_agents/skills/create-agentsmd/SKILL.md" ]
}

@test "catalog defines provider coverage outputs" {
	grep -q 'supportReport' "$SETS"
	grep -q 'providerErrors' "$SETS"
	grep -q 'darwinCasks' "$SETS"
	grep -q 'linuxSystemModules' "$SETS"
}

@test "catalog rejects incomplete extra and inactive-platform provider metadata" {
	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"
	command -v jq >/dev/null 2>&1 || skip "jq is not available in this test environment"

	nix_fixture_errors '{
		missing-source = {
			pkg = pkgs.hello;
			category = "test";
			support = {
				windows = { unsupported = "fixture"; };
				darwin = { provider = "nix"; source = ""; identity = "missing-source"; nixAttr = "hello"; };
				linux = { unsupported = "fixture"; };
			};
		};
		missing = {
			pkg = pkgs.hello;
			category = "test";
			support = {
				windows = { unsupported = "fixture"; };
				darwin = { provider = "nix"; source = "nixpkgs"; identity = ""; nixAttr = ""; };
				linux = { unsupported = "fixture"; };
			};
		};
		missing-cask = {
			category = "test";
			support = {
				windows = { unsupported = "fixture"; };
				darwin = { provider = "homebrew-cask"; source = "homebrew"; identity = ""; cask = ""; };
				linux = { unsupported = "fixture"; };
			};
		};
		extra = {
			pkg = pkgs.hello;
			category = "test";
			support = {
				windows = { unsupported = "fixture"; };
				darwin = { provider = "nix"; source = "nixpkgs"; identity = "extra"; nixAttr = "hello"; cask = "wrong"; };
				linux = { unsupported = "fixture"; };
			};
		};
		orphan = {
			category = "test";
			support = {
				windows = { unsupported = "fixture"; };
				darwin = { unsupported = "fixture"; cask = "stale"; };
				linux = { unsupported = "fixture"; };
			};
		};
		inactive-invalid = {
			pkg = "not-a-derivation";
			category = "test";
			support = {
				windows = { unsupported = "fixture"; };
				darwin = { unsupported = "fixture"; };
				linux = { provider = "nix"; source = "nixpkgs"; identity = "inactive-invalid"; nixAttr = "hello"; };
			};
		};
		inactive-platform = {
			pkg = pkgs.hello.overrideAttrs (_: { meta.platforms = [ "aarch64-darwin" ]; });
			category = "test";
			support = {
				windows = { unsupported = "fixture"; };
				darwin = { unsupported = "fixture"; };
				linux = { provider = "nix"; source = "nixpkgs"; identity = "inactive-platform"; nixAttr = "hello"; };
			};
		};
		inactive-null = {
			pkg = null;
			category = "test";
			support = {
				windows = { unsupported = "fixture"; };
				darwin = { unsupported = "fixture"; };
				linux = { provider = "nix"; source = "nixpkgs"; identity = "inactive-null"; nixAttr = "hello"; };
			};
		};
	}'
	[ "$status" -eq 0 ]
	run jq -e '
		any(.[]; contains("missing-source: darwin: provider requires source")) and
		any(.[]; contains("missing: darwin: provider requires identity")) and
		any(.[]; contains("missing: darwin: source = nixpkgs requires nixAttr")) and
		any(.[]; contains("missing-cask: darwin: homebrew-cask provider requires cask")) and
		any(.[]; contains("extra: darwin: nix provider cannot include cask")) and
		any(.[]; contains("extra: darwin: catalog ID appears in both Nix and Homebrew resolution")) and
		any(.[]; contains("orphan: darwin: providerless metadata cannot include cask")) and
		any(.[]; contains("inactive-invalid: linux: nix provider requires a derivation")) and
		any(.[]; contains("inactive-platform: linux: nix provider derivation does not support linux")) and
		any(.[]; contains("inactive-null: linux: nix provider requires a derivation"))
	' <<<"$output"
	[ "$status" -eq 0 ]
}

@test "Node.js follows the current nixpkgs major" {
	run awk '
		/^[[:space:]]*nodejs = \{/ { in_entry=1 }
		in_entry { print }
		in_entry && /^        };$/ { exit }
	' "$SETS"
	[ "$status" -eq 0 ]
	[[ "$output" == *'pkg = pkgs.nodejs;'* ]]
	[[ "$output" != *'nodejs_24'* ]]
}

@test "DeepSeek Harness is managed as a cross-platform pnpm package" {
	grep -q '"@deepseek-ai/dsh"' "$SETS"
	grep -q '"@deepseek-ai/dsh"' "$REPO_ROOT/chezmoi/.chezmoidata/pnpm_global.yaml"
	grep -q '"@deepseek-ai/dsh"' "$REPO_ROOT/windows/pnpm/packages.json"
	grep -q 'command = "dsh";' "$SETS"
}

@test "DeepSeek Harness native builds are pre-approved for pnpm global installs" {
	for build_package in \
		"@deepseek-ai/dsh-subprocess-local" \
		"@google/genai" \
		koffi \
		node-pty \
		protobufjs; do
		grep -q -- "--allow-build=$build_package" "$SETS"
		grep -q -- "--allow-build=$build_package" "$REPO_ROOT/chezmoi/.chezmoiscripts/run_onchange_install-pnpm-global.sh.tmpl"
		grep -q -- "--allow-build=$build_package" "$REPO_ROOT/windows/pnpm/packages.json"
	done
	grep -q 'pnpm add -g.*PNPM_BUILD_ARGS' "$REPO_ROOT/chezmoi/.chezmoiscripts/run_onchange_install-pnpm-global.sh.tmpl"
}

@test "DeepSeek Harness is reinstalled when the native build approval changes" {
	grep -q 'pnpm remove -g.*PKG_NAME' "$REPO_ROOT/chezmoi/.chezmoiscripts/run_onchange_install-pnpm-global.sh.tmpl"
}

@test "pnpm v11 global installs skip packages present in the global manifest" {
	test_dir="$(mktemp -d)"
	mkdir -p "$test_dir/bin"

	cat > "$test_dir/bin/pnpm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "list" ] && [ "${2:-}" = "-g" ]; then
	cat <<'JSON'
[{"dependencies":{
  "@prisma/language-server":{"version":"31.11.0"},
  "@agentclientprotocol/claude-agent-acp":{"version":"0.70.0"},
  "@deepseek-ai/dsh":{"version":"0.1.1-rc.2"},
  "@playwright/cli":{"version":"0.1.18"},
  "typescript-language-server":{"version":"6.0.0"},
  "typescript":{"version":"7.0.2"}
}}]
JSON
	exit 0
fi

exit 1
EOF
	chmod +x "$test_dir/bin/pnpm"

	for package_name in \
		"@prisma/language-server" \
		"@agentclientprotocol/claude-agent-acp" \
		"@deepseek-ai/dsh" \
		"@playwright/cli" \
		typescript-language-server \
		typescript; do
		run env PATH="$test_dir/bin:$PATH" \
			bash -c 'source "$1" && pnpm_global_package_installed "$2"' \
			bash "$REPO_ROOT/chezmoi/.chezmoitemplates/pnpm_global_installed.sh" "$package_name"
		[ "$status" -eq 0 ]
	done

	run env PATH="$test_dir/bin:$PATH" \
		bash -c 'source "$1" && pnpm_global_package_installed "$2"' \
		bash "$REPO_ROOT/chezmoi/.chezmoitemplates/pnpm_global_installed.sh" missing-package
	[ "$status" -ne 0 ]

	rm -rf "$test_dir"
}

@test "cross-platform applications are not classified as Windows-only" {
	windows_only="$(sed -n '/windowsOnly = {/,/^  };/p' "$SETS")"
	for package_id in \
		Docker.DockerDesktop \
		dprint.dprint \
		hadolint.hadolint \
		Google.Chrome \
		Microsoft.VisualStudioCode \
		OpenAI.Codex \
		Oven-sh.Bun \
		zig.zig; do
		[[ "$windows_only" != *"\"$package_id\""* ]]
	done
}

@test "Docker declares Darwin cask and Linux system providers" {
	run awk '
		/docker-desktop = \{/ { in_entry=1 }
		in_entry { print }
		in_entry && /^        };/ { exit }
	' "$SETS"
	[ "$status" -eq 0 ]
	[[ "$output" == *'winget = "Docker.DockerDesktop"'* ]]
	[[ "$output" == *'cask = "docker-desktop"'* ]]
	[[ "$output" == *'systemModule = "docker"'* ]]
}

@test "true Windows-only packages carry unsupported reasons" {
	grep -q 'windowsOnlySupport' "$SETS"
	grep -q 'Microsoft.PowerToys' "$SETS"
	grep -q 'Windows system utility' "$SETS"
}

@test "support report derivation and CI gate are wired" {
	grep -q 'package-support-report' "$REPO_ROOT/nix/flakes/packages.nix"
	grep -q 'package-provider-coverage' "$REPO_ROOT/nix/flakes/packages.nix"
	grep -q 'Verify package provider coverage' "$REPO_ROOT/.github/workflows/ci-consistency.yml"
}

@test "winget export reproduces committed Windows manifests byte-for-byte" {
	run --separate-stderr nix build "path:$REPO_ROOT#winget-export" --no-link --print-out-paths
	[ "$status" -eq 0 ]
	[ -d "$output" ]

	cmp "$output/winget/packages.json" "$REPO_ROOT/windows/winget/packages.json"
	cmp "$output/npm/packages.json" "$REPO_ROOT/windows/npm/packages.json"
	cmp "$output/pnpm/packages.json" "$REPO_ROOT/windows/pnpm/packages.json"
}

@test "missing providers require an explicitly reviewed unsupported reason" {
	grep -q 'reviewedUnsupported' "$SETS"
	grep -q 'missing.*provider or reviewed unsupported reason' "$SETS"
	! grep -q '{ unsupported = "No Windows provider is configured"; }' "$SETS"
}

@test "catalog Winget packages preserve ID-keyed metadata" {
	grep -q 'attachWingetIdMetadata' "$REPO_ROOT/nix/packages/winget.nix"
	grep -q 'attachWingetIdMetadata id' "$REPO_ROOT/nix/packages/winget.nix"
}

@test "macOS desktop casks include Raycast Dia and Orca" {
	grep -q 'raycast = {' "$SETS"
	grep -q 'cask = "raycast"' "$SETS"
	grep -q 'dia-browser = {' "$SETS"
	grep -q 'cask = "thebrowsercompany-dia"' "$SETS"
	grep -q 'orca-editor = {' "$SETS"
	grep -q 'cask = "stablyai/orca/orca"' "$SETS"
}

@test "Visual Studio Code uses the unmodified nixpkgs application with migration metadata" {
	run awk '
		/^[[:space:]]*vscode = \{/ { in_entry=1 }
		in_entry { print }
		in_entry && /^        };$/ { exit }
	' "$SETS"
	[ "$status" -eq 0 ]
	[[ "$output" == *'pkg = pkgs.vscode;'* ]]
	[[ "$output" == *'provider = "nix";'* ]]
	[[ "$output" == *'source = "nixpkgs";'* ]]
	[[ "$output" == *'nixAttr = "vscode";'* ]]
	[[ "$output" == *'homepage = "https://code.visualstudio.com/";'* ]]
	[[ "$output" == *'appName = "Visual Studio Code.app";'* ]]
	[[ "$output" == *'bundleId = "com.microsoft.VSCode";'* ]]
	[[ "$output" == *'executable = "Code";'* ]]
	[[ "$output" == *'legacyDarwin = {'* ]]
	[[ "$output" == *'provider = "homebrew-cask";'* ]]
	[[ "$output" == *'name = "visual-studio-code";'* ]]
	[[ "$output" != *'useVSCodeRipgrep'* ]]
	[[ "$output" != *'postPatch'* ]]
	[[ "$output" != *'cask = "visual-studio-code"'* ]]
}

@test "Darwin routes Nix GUI apps to system packages and keeps commands in Home Manager" {
	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"
	command -v jq >/dev/null 2>&1 || skip "jq is not available in this test environment"

	nix_fixture_darwin_package_split
	[ "$status" -eq 0 ]
	run jq -e '
		.default == {
			"guiSystem": false,
			"guiHome": false,
			"commandSystem": false,
			"commandHome": true
		}
		and .enabled == {
			"guiSystem": true,
			"guiHome": false,
			"commandSystem": false,
			"commandHome": true
		}
	' <<<"$output"
	[ "$status" -eq 0 ]
}

@test "Arc remains Windows-only and Dia remains macOS-only" {
	run grep -n -A18 '^[[:space:]]*arc-browser = {' "$SETS"
	[ "$status" -eq 0 ]
	[[ "$output" == *'winget = "TheBrowserCompany.Arc"'* ]]
	[[ "$output" == *'unsupported = "Use Dia instead of Arc on macOS"'* ]]
	[[ "$output" != *'cask = "arc"'* ]]

	run grep -n -A12 '^[[:space:]]*dia-browser = {' "$SETS"
	[ "$status" -eq 0 ]
	[[ "$output" == *'cask = "thebrowsercompany-dia"'* ]]
}

@test "Discord is a cross-platform desktop package" {
	run grep -n -A12 '^[[:space:]]*discord = {' "$SETS"
	[ "$status" -eq 0 ]
	[[ "$output" == *'pkg = pkgs.discord;'* ]]
	[[ "$output" == *'winget = "Discord.Discord";'* ]]
	[[ "$output" == *'category = "desktop";'* ]]
	[[ "$output" == *'provider = "homebrew-cask";'* ]]
	[[ "$output" == *'cask = "discord"'* ]]
}

@test "WSL excludes the native Discord package" {
	run grep -n -A3 'homeExtraSpecialArgs' "$REPO_ROOT/nix/flakes/hosts.nix"
	[ "$status" -eq 0 ]
	[[ "$output" == *'isWSL = true;'* ]]
}

@test "generated Windows manifest contains Discord" {
	command -v jq >/dev/null 2>&1 || skip "jq is not available in this test environment"
	run jq -e '
		[.Sources[] | select(.SourceDetails.Name == "winget") | .Packages[]
		 | select(.PackageIdentifier == "Discord.Discord")] | length == 1
	' "$REPO_ROOT/windows/winget/packages.json"
	[ "$status" -eq 0 ]
}

@test "WezTerm uses the nightly Homebrew cask on Darwin and Nix on Linux" {
	run awk '
		/wezterm = \{/ { in_entry=1 }
		in_entry { print }
		in_entry && /^        };/ { exit }
	' "$SETS"
	[ "$status" -eq 0 ]
	[[ "$output" == *'pkg = pkgs.wezterm;'* ]]
	[[ "$output" == *'cask = "wezterm@nightly"'* ]]
	[[ "$output" == *'darwin = {'* ]]
	[[ "$output" == *'linux = {'* ]]
	[[ "$output" == *'provider = "homebrew-cask"'* ]]
	[[ "$output" == *'provider = "nix"'* ]]
}

@test "Ollama has native Nix, Homebrew cask, and Winget catalog providers with verification" {
	run awk '
		/^[[:space:]]*ollama = \{/ { in_entry=1 }
		in_entry { print }
		in_entry && /^        };/ { exit }
	' "$SETS"
	[ "$status" -eq 0 ]
	[[ "$output" == *'pkg = pkgs.ollama;'* ]]
	[[ "$output" == *'winget = "Ollama.Ollama";'* ]]
	[[ "$output" == *'category = "llm";'* ]]
	[[ "$output" == *'provider = "homebrew-cask";'* ]]
	[[ "$output" == *'cask = "ollama-app";'* ]]
	[[ "$output" == *'provider = "nix";'* ]]

	run awk '
		/^  wingetVerify = \{/ { in_section=1 }
		in_section && /^[[:space:]]*ollama = \{/ { in_entry=1 }
		in_entry { print }
		in_entry && /^        };/ { exit }
	' "$SETS"
	[ "$status" -eq 0 ]
	[[ "$output" == *'command = "ollama";'* ]]
	[[ "$output" == *'args = [ "--version" ];'* ]]
}

@test "ChatGPT desktop has native Linux, Darwin cask, and Microsoft Store providers" {
	run awk '
		/^[[:space:]]*chatgpt = \{/ { in_entry=1 }
		in_entry { print }
		in_entry && /^        };/ { exit }
	' "$SETS"
	[ "$status" -eq 0 ]
	[[ "$output" == *'pkg = linuxOnlyPackage (pkgs.callPackage ./chatgpt { });'* ]]
	[[ "$output" == *'msstore = "9NT1R1C2HH7J";'* ]]
	[[ "$output" == *'cask = "chatgpt"'* ]]
	[[ "$output" == *'provider = "nix"'* ]]
}

@test "ChatGPT Linux package is wired as a reproducible Nix derivation" {
	[ -f "$REPO_ROOT/nix/packages/chatgpt/default.nix" ]
	grep -q 'persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.818.41705_amd64.deb' "$REPO_ROOT/nix/packages/chatgpt/default.nix"
	grep -q 'persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.818.41705_arm64.deb' "$REPO_ROOT/nix/packages/chatgpt/default.nix"
	! grep -q '/latest/chatgpt_' "$REPO_ROOT/nix/packages/chatgpt/default.nix"
	grep -q 'sha256-' "$REPO_ROOT/nix/packages/chatgpt/default.nix"
}

@test "ChatGPT Linux package supplies Qt runtimes and ignores optional musl modules" {
	grep -q '^    (lib\.getLib qt5\.qtbase)$' "$REPO_ROOT/nix/packages/chatgpt/default.nix"
	grep -q '^    (lib\.getLib qt6\.qtbase)$' "$REPO_ROOT/nix/packages/chatgpt/default.nix"
	grep -q 'autoPatchelfIgnoreMissingDeps' "$REPO_ROOT/nix/packages/chatgpt/default.nix"
	grep -q 'libc\.musl-x86_64\.so\.1' "$REPO_ROOT/nix/packages/chatgpt/default.nix"
	grep -q 'libc\.musl-aarch64\.so\.1' "$REPO_ROOT/nix/packages/chatgpt/default.nix"
}

@test "ChatGPT Linux package uses the normal Nix output layout" {
	grep -q 'cp -R "\$unpacked/usr/." "\$out/"' "$REPO_ROOT/nix/packages/chatgpt/default.nix"
	grep -q 'makeWrapper "\$out/lib/chatgpt/ChatGPT"' "$REPO_ROOT/nix/packages/chatgpt/default.nix"
}

@test "Darwin evaluation installs WezTerm nightly and its terminfo" {
	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"

	run --separate-stderr env DOTFILES_USER=codex DOTFILES_HOME=/Users/codex nix eval --impure --json --expr "
		let
		  flake = builtins.getFlake (toString $REPO_ROOT);
		  config = flake.darwinConfigurations.macos.config;
		  caskNames = builtins.map (cask: if builtins.isString cask then cask else cask.name) config.homebrew.casks;
		  homePackages = config.home-manager.users.codex.home.packages;
		in {
			casks = builtins.filter (name: name == \"wezterm@nightly\") caskNames;
		  terminfoPackages = builtins.map (package: package.name) (
		    builtins.filter (package: package.name == \"wezterm-terminfo\") homePackages
		  );
		}
	"
	[ "$status" -eq 0 ]
	[ "$output" = '{"casks":["wezterm@nightly"],"terminfoPackages":["wezterm-terminfo"]}' ]
}

@test "Warp is removed from the package catalog" {
	! grep -q 'warp-terminal' "$SETS"
	! grep -q 'Warp.Warp' "$SETS"
	! grep -q 'warpInnoLatest' "$SETS"
}

@test "terminal keybinding helpers have platform-scoped providers" {
	run awk '
		/^[[:space:]]*hammerspoon = \{/ { in_entry=1 }
		in_entry { print }
		in_entry && /^        };/ { exit }
	' "$SETS"
	[ "$status" -eq 0 ]
	[[ "$output" == *'category = "terminal"'* ]]
	[[ "$output" == *'provider = "homebrew-cask"'* ]]
	[[ "$output" == *'cask = "hammerspoon"'* ]]

	run awk '
		/^[[:space:]]*autohotkey = \{/ { in_entry=1 }
		in_entry { print }
		in_entry && /^        };/ { exit }
	' "$SETS"
	[ "$status" -eq 0 ]
	[[ "$output" == *'winget = "AutoHotkey.AutoHotkey"'* ]]
	[[ "$output" == *'category = "terminal"'* ]]
	[[ "$output" == *'provider = "winget"'* ]]
}
