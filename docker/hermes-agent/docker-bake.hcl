group "default" {
  targets = ["bootstrap-test", "bootstrap-runtime"]
}

target "common" {
  context    = "docker"
  dockerfile = "hermes-agent/Dockerfile"
}

target "bootstrap-test" {
  inherits = ["common"]
  target   = "hermes-bootstrap-test"
  tags     = ["local/hermes-bootstrap-test"]
}

target "bootstrap-runtime" {
  inherits = ["common"]
  target   = "hermes-bootstrap-runtime"
  tags     = ["local/hermes-agent-gh:latest"]
}
