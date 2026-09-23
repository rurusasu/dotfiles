{ inputs }:
let
  systems = {
    x86_64-linux = "x86_64-linux";
    aarch64-linux = "aarch64-linux";
  };
  pkgsBySystem = builtins.mapAttrs (
    _: system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    }
  ) systems;
  darwinSystem = "aarch64-darwin";
  selectionPkgsBySystem = pkgsBySystem // {
    ${darwinSystem} = import inputs.nixpkgs {
      system = darwinSystem;
      config.allowUnfree = true;
    };
  };
  setsBySystem = builtins.mapAttrs (
    _: pkgs:
    import ../packages/sets.nix {
      inherit pkgs;
      inherit (pkgs) lib;
      codexPackage = pkgs.hello;
    }
  ) selectionPkgsBySystem;
  chatgptBySystem = builtins.mapAttrs (
    name: _: pkgsBySystem.${name}.callPackage ../packages/chatgpt { }
  ) systems;
  packageContract = system:
    let
      pkgs = pkgsBySystem.${system};
      chatgpt = chatgptBySystem.${system};
    in
    {
      hasQt5Runtime = builtins.elem (pkgs.lib.getLib pkgs.qt5.qtbase) chatgpt.buildInputs;
      hasQt6Runtime = builtins.elem (pkgs.lib.getLib pkgs.qt6.qtbase) chatgpt.buildInputs;
      ignoredOptionalMuslModules = chatgpt.autoPatchelfIgnoreMissingDeps;
    };
in
{
  testChatGPTPackageSelectionRemainsHostDependent = {
    expr = {
      darwin = builtins.map (package: package.drvPath) (
        setsBySystem.${darwinSystem}.resolveForInstallFeatures [ ] [ "chatgpt" ]
      );
      linux = builtins.mapAttrs (
        system: _:
        builtins.map (package: package.drvPath) (
          setsBySystem.${system}.resolveForInstallFeatures [ ] [ "chatgpt" ]
        )
      ) chatgptBySystem;
    };
    expected = {
      darwin = [ selectionPkgsBySystem.${darwinSystem}.chatgpt.drvPath ];
      linux = builtins.mapAttrs (_: package: [ package.drvPath ]) chatgptBySystem;
    };
  };

  testChatGPTLinuxPreservesQtRuntimesAndOptionalMuslModules = {
    expr = builtins.mapAttrs (_: packageContract) systems;
    expected = {
      x86_64-linux = {
        hasQt5Runtime = true;
        hasQt6Runtime = true;
        ignoredOptionalMuslModules = [
          "libc.musl-x86_64.so.1"
          "libc.musl-aarch64.so.1"
        ];
      };
      aarch64-linux = {
        hasQt5Runtime = true;
        hasQt6Runtime = true;
        ignoredOptionalMuslModules = [
          "libc.musl-x86_64.so.1"
          "libc.musl-aarch64.so.1"
        ];
      };
    };
  };

  testChatGPTLinuxInstallPhaseDeclaresResourceAndWrapperCommands = {
    expr = builtins.mapAttrs (
      _: system:
      let
        installPhase = chatgptBySystem.${system}.installPhase;
      in
      builtins.hasInfix ''cp -R "$unpacked/usr/." "$out/"'' installPhase
      && builtins.hasInfix ''makeWrapper "$out/lib/chatgpt/ChatGPT" "$out/bin/chatgpt"'' installPhase
    ) systems;
    expected = {
      x86_64-linux = true;
      aarch64-linux = true;
    };
  };
}
