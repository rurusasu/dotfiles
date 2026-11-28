{
  services.tailscale.enable = true;
  # Keep SSH public-key authentication with the 1Password agent.
  services.tailscale.extraSetFlags = [ "--ssh=false" ];
}
