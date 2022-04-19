group "default" {
  #targets = ["parsec", "parsec_0_8_1", "parsec_1", "parsec_tpm"]
  targets = ["parsec_1"]
}
target "generic" {
  context = "."
  args = {
    REGISTRY = "parallaxsecond"
  }
}
target "parsec" {
  inherits = ["generic"]
  context = "./parsec"
  args = {
    PARSEC_BRANCH = "main"
  }
  tags = [
    "parallaxsecond/parsec:latest"
  ]
}
target "parsec_0_8_1" {
  inherits = ["parsec"]
  args = {
    PARSEC_BRANCH = "0.8.1"
  }
  tags = [
    "parallaxsecond/parsec:0.8.1"
  ]
}
target "parsec_tpm" {
  inherits = ["parsec"]
  args = {
    PARSEC_CONFIG = "config_tpm.toml"
  }
  tags = [
    "parallaxsecond/parsec:1.0.0tpm"
  ]
}
target "parsec_1" {
  inherits = ["parsec"]
  args = {
    PARSEC_BRANCH = "1.0.0"
  }
  tags = [
    "parallaxsecond/parsec:1.0.0"
  ]
}
