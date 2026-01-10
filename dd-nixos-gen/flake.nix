{
  description = "nixos image for dd-install";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators }:
    let
      system = "x86_64-linux";

      baseConfig = { config, pkgs, lib, modulesPath, ... }: {
        imports = [
          "${modulesPath}/profiles/minimal.nix"
        ];

        nix.registry = lib.mkForce {};
        # nix.registry.nixpkgs.to = {
        #   type = "github";
        #   owner = "NixOS";
        #   repo = "nixpkgs";
        #   ref = "nixos-25.05";
        # };

        # BIOS boot
        boot.loader.grub = {
          enable = true;
          device = lib.mkForce "/dev/sda";
          efiSupport = false;
        };

        # serial console for QEMU
        boot.kernelParams = [ "console=tty0" "console=ttyS0,115200" ];
        boot.loader.grub.extraConfig = ''
          terminal_input console serial
          terminal_output console serial
          serial --unit=0 --speed=115200
        '';

        boot.initrd.availableKernelModules = [
          "virtio_pci" "virtio_blk" "virtio_scsi"
          "ahci" "xhci_pci"
          "sd_mod" "sr_mod" "ata_piix"
        ];

        fileSystems."/" = lib.mkForce {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
          options = [ "noatime" ];
        };

        fileSystems."/var/lib" = lib.mkForce {
          device = "/dev/disk/by-label/varlib";
          fsType = "ext4";
          options = [ "noatime" ];
        };

        networking.hostName = "server";
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

        time.timeZone = "UTC";

        # keys for initial boot
        users.users.root.openssh.authorizedKeys.keys =
          if builtins.pathExists ./authorized_keys
          then lib.splitString "\n" (lib.removeSuffix "\n" (builtins.readFile ./authorized_keys))
          else [];

        # minimal
        boot.enableContainers = false;
        boot.initrd.compressor = "zstd";
        boot.initrd.includeDefaultModules = false;
        # boot.initrd.kernelModules = [ "ext4" ... ];
        boot.initrd.systemd.enable = lib.mkForce false;
        boot.kernelPackages = pkgs.linuxPackages_hardened; # linuxPackages_latest;
        # disabledModules = [
        #   <nixpkgs/nixos/modules/profiles/all-hardware.nix>
        #   <nixpkgs/nixos/modules/profiles/base.nix>
        # ];
        documentation.enable = false;
        # documentation.doc.enable = false;
        # documentation.info.enable = false;
        # documentation.man.enable = false;
        # documentation.nixos.enable = false;
        environment.defaultPackages = lib.mkForce [];
        environment.systemPackages = with pkgs; [
          nano
          curl
        ];
        environment.stub-ld.enable = false;
        fonts.fontconfig.enable = false;
        hardware.enableRedistributableFirmware = false;
        hardware.firmware = [];
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

        system.stateVersion = "25.05";
      };

      nixosSystem = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          baseConfig
          { virtualisation.diskSize = "auto"; }
        ];
      };

    in
    {
      packages.x86_64-linux = {
        cpx11 = nixos-generators.nixosGenerate {
          inherit system;
          format = "raw";
          modules = [
            baseConfig
            {
              virtualisation.diskSize = "auto";
            }
          ];
        };
      };

      packages.x86_64-linux.default = self.packages.x86_64-linux.cpx11;

      nixosConfigurations.cpx11 = nixosSystem;
    };
}
