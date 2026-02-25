{
  description = "nixos image for dd-install";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko }:
    let
      system = "x86_64-linux";

      boot = if builtins.getEnv "BOOT" != "" then builtins.getEnv "BOOT" else "bios";

      # configuration shared by all server types
      baseConfig = { config, pkgs, lib, modulesPath, ... }: {
        imports = [
          "${modulesPath}/profiles/minimal.nix"
          "${modulesPath}/profiles/qemu-guest.nix"
          disko.nixosModules.disko
          ./disco-${boot}.nix
        ];

        nix.registry = lib.mkForce {};

        # boot loader
        boot.loader.grub.enable = true;
        boot.loader.grub.efiSupport = boot == "efi";
        boot.loader.grub.efiInstallAsRemovable = boot == "efi";
        boot.loader.grub.device = if boot == "efi" then "nodev" else lib.mkDefault "/dev/sda";

        boot.initrd.availableKernelModules = [ "ahci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];

        # fileSystems are defined by disko in disco-*.nix

        networking.hostName = "server";  # generic, will be changed post-install
        networking.useDHCP = true;
        networking.firewall.enable = true;
        networking.firewall.allowedTCPPorts = [ 22 ];

        services.openssh = {
          enable = true;
          settings = {
            PermitRootLogin = "prohibit-password";
            PasswordAuthentication = false;
          };
        };

        # cloud-init for Hetzner
        services.cloud-init = {
          enable = true;
          network.enable = true;
          settings = {
            datasource_list = [ "Hetzner" "None" ];
            disable_root = false;
            users = [];
          };
        };

        time.timeZone = "UTC";

        # keys for initial boot
        # users.users.root.openssh.authorizedKeys.keys =
        #   if builtins.pathExists ./authorized_keys
        #   then lib.splitString "\n" (lib.removeSuffix "\n" (builtins.readFile ./authorized_keys))
        #   else [];
        users.users.root.openssh.authorizedKeys.keys = lib.splitString "\n" (lib.removeSuffix "\n" (builtins.readFile ./authorized_keys));

        # minimal
        boot.enableContainers = false;
        boot.initrd.compressor = "zstd";
        boot.initrd.systemd.suppressedUnits = lib.mkIf config.systemd.enableEmergencyMode [
          "emergency.service"
          "emergency.target"
        ];
        boot.initrd.systemd.enable = lib.mkForce false;
        boot.kernelPackages = pkgs.linuxPackages;
        documentation.enable = false;
        environment.defaultPackages = lib.mkForce [];
        environment.systemPackages = with pkgs; [
          nano
          curl
          e2fsprogs
        ];
        environment.stub-ld.enable = false;
        fonts.fontconfig.enable = false;
        hardware.enableRedistributableFirmware = false;
        hardware.firmware = [];
        i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];
        nix.channel.enable = false;
        programs.bash.completion.enable = false;
        programs.command-not-found.enable = false;
        programs.vim.defaultEditor = false;
        security.audit.enable = false;
        security.polkit.enable = false;
        services.udisks2.enable = false;
        system.extraDependencies = [];
        system.disableInstallerTools = true;
        xdg.autostart.enable = false;
        xdg.icons.enable = false;
        xdg.mime.enable = false;
        xdg.sounds.enable = false;
        system.stateVersion = "25.11";
      };

      # server type configurations (Hetzner cloud server types)
      servers = {
        cpx = {
          # add server-type-specific overrides here (disk size, etc.)
        };
      };

      # generate nixosConfigurations for each server type
      mkNixosConfig = name: cfg: nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          baseConfig
          # add server-type-specific modules here if needed
        ];
      };

      # generate packages (disk images) for each server
      mkImagePackage = name: self.nixosConfigurations.${name}.config.system.build.diskoImages;

    in
    {
      nixosConfigurations = builtins.mapAttrs mkNixosConfig servers;

      packages.x86_64-linux = builtins.mapAttrs (name: _: mkImagePackage name) servers // {
        default = self.packages.x86_64-linux.cpx;
      };
    };
}
