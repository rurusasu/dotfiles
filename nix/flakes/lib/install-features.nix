{
  lib,
  withHermes ? false,
  withDocker ? false,
  withOllama ? false,
}:
let
  includeOllama = withOllama || withDocker;
in
lib.optionals includeOllama [ "WithOllama" ]
++ lib.optionals withDocker [ "WithDocker" ]
++ lib.optionals withHermes [ "WithHermes" ]
