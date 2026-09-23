{ inputs }:
let
  system = "x86_64-linux";
  systemManagerConfig = inputs.system-manager.lib.makeSystemConfig {
    specialArgs = {
      inherit inputs;
      dotfilesUser = "test-user";
      dotfilesHome = "/srv/dotfiles/test-user";
      dotfilesUid = "4242";
      dotfilesGid = "4243";
      dotfilesGroup = "test-primary";
    };
    modules = [
      inputs.home-manager.nixosModules.home-manager
      {
        nixpkgs.hostPlatform = system;
        nixpkgs.config.allowUnfree = true;
      }
      ../system-manager/default.nix
    ];
  };
  config = systemManagerConfig.config;

  # Return the generated script as its Nix value so the bind contract can be
  # evaluated without building or starting the Ollama service.
  scriptPkgs = {
    iproute2 = "/nix/store/iproute2";
    gawk = "/nix/store/gawk";
    ollama = "/nix/store/ollama";
    writeShellScript = _name: text: text;
  };
  ollamaModule = import ../system-manager/ollama.nix { pkgs = scriptPkgs; };
  ollamaExecStart = ollamaModule.systemd.services.ollama.serviceConfig.ExecStart;
in
{
  testSystemManagerComposesHomeManagerAndEnablesNix = {
    expr = {
      homeManagerUserConfigured = builtins.hasAttr "test-user" config.home-manager.users;
      nixEnabled = config.nix.enable;
    };
    expected = {
      homeManagerUserConfigured = true;
      nixEnabled = true;
    };
  };

  testSystemManagerOllamaBindsToDockerBridgeGateway = {
    expr = {
      resolvesDockerBridgeAddress = inputs.nixpkgs.lib.hasInfix
        "ip -4 -o addr show dev docker0"
        ollamaExecStart;
      bindsToResolvedGateway = inputs.nixpkgs.lib.hasInfix
        ''export OLLAMA_HOST="$docker_gateway:11434"''
        ollamaExecStart;
      avoidsWildcardBind = !(inputs.nixpkgs.lib.hasInfix "0.0.0.0:11434" ollamaExecStart);
    };
    expected = {
      resolvesDockerBridgeAddress = true;
      bindsToResolvedGateway = true;
      avoidsWildcardBind = true;
    };
  };
}
