check:
  nix flake check --show-trace --all-systems

eval:
  nix eval .#nixosConfigurations.cpx.config.system.build.toplevel.drvPath
  nix eval .#cpx.config.environment.systemPackages --json | jq '.[].name'
  nix eval .#cpx.config.systemd.packages --json | jq '.[].name'

paths:
  nix path-info -rsSh .#packages.x86_64-linux.cpx.config.system.build.toplevel 2>&1 | tail -30
  nix path-info -rsSh .#nixosConfigurations.cpx.config.system.build.toplevel 2>&1 | tail -30

build:
  nix build .#cpx --system x86_64-linux
