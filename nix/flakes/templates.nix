{ ... }: {
  flake = {
    templates = {
      python = {
        path = ../templates/python;
        description = "Python development environment with uv and ruff";
      };
    };
  };
}
