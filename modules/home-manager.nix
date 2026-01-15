# Copyright (c) 2019-2022, see AUTHORS. Licensed under MIT License, see LICENSE.

{ config, lib, pkgs, home-manager-path, ... }:

with lib;

let
  cfg = config.home-manager;

  extendedLib = import (home-manager-path + "/modules/lib/stdlib-extended.nix") lib;

  hmModule = types.submoduleWith {
    specialArgs = { lib = extendedLib; } // cfg.extraSpecialArgs;
    modules = [
      ({ name, ... }: {
        imports = import (home-manager-path + "/modules/modules.nix") {
          inherit pkgs;
          lib = extendedLib;
          useNixpkgsModule = !cfg.useGlobalPkgs;
        };

        config = {
          submoduleSupport.enable = true;
          submoduleSupport.externalPackageInstall = cfg.useUserPackages;

          home.username = config.user.userName;
          home.homeDirectory = config.user.home;
        };
      })
    ] ++ cfg.sharedModules;
  };
in

{

  ###### interface

  options = {

    home-manager = {
      backupFileExtension = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "backup";
        description = ''
          On activation move existing files by appending the given
          file extension rather than exiting with an error.
        '';
      };

      config = mkOption {
        type = types.nullOr hmModule;
        default = null;
        # Prevent the entire submodule being included in the documentation.
        visible = "shallow";
        description = ''
          Home Manager configuration, see
          <link xlink:href="https://nix-community.github.io/home-manager/options.html" />.
        '';
      };

      extraSpecialArgs = mkOption {
        type = types.attrs;
        default = { };
        example = literalExpression "{ inherit emacs-overlay; }";
        description = ''
          Extra <literal>specialArgs</literal> passed to Home Manager. This
          option can be used to pass additional arguments to all modules.
        '';
      };

      sharedModules = mkOption {
        type = with types; listOf raw;
        default = [ ];
        example = literalExpression "[ { home.packages = [ nixpkgs-fmt ]; } ]";
        description = ''
          Extra modules.
        '';
      };

      useGlobalPkgs = mkEnableOption ''
        using the system configuration's <literal>pkgs</literal>
        argument in Home Manager. This disables the Home Manager
        options <option>nixpkgs.*</option>
      '';

      useUserPackages = mkEnableOption ''
        installation of user packages through the
        <option>environment.packages</option> option.
      '' // {
        default = versionAtLeast config.system.stateVersion "20.09";
      };
    };

  };


  ###### implementation

  config = mkIf (cfg.config != null) {

    inherit (cfg.config) assertions warnings;

    build = {
      activationBefore = mkIf cfg.useUserPackages {
        setPriorityHomeManagerPath = ''
          # Check if using new nix profile format (manifest.json) or old nix-env format
          if [[ -e "${config.user.home}/.nix-profile/manifest.json" ]]; then
            # New nix profile format - priority is set at install time
            # Check if home-manager-path exists and needs priority adjustment
            # Strip ANSI color codes from output before checking
            if nix profile list 2>/dev/null | sed 's/\x1B\[[0-9;]*m//g' | grep -q "home-manager-path"; then
              # Note: nix profile doesn't support changing priority after install
              # Priority should be set during home-manager activation instead
              $VERBOSE_ECHO "home-manager-path found in nix profile (priority set at install time)"
            fi
          else
            # Old nix-env format
            if nix-env -q 2>/dev/null | grep -q '^home-manager-path$'; then
              $DRY_RUN_CMD nix-env $VERBOSE_ARG --set-flag priority 120 home-manager-path
            fi
          fi
        '';
      };

      activationAfter.homeManager = concatStringsSep " " (
        optional
          (cfg.backupFileExtension != null)
          "HOME_MANAGER_BACKUP_EXT='${cfg.backupFileExtension}'"
        ++ [ "${cfg.config.home.activationPackage}/activate" ]
      );
    };

    environment.packages = mkIf cfg.useUserPackages cfg.config.home.packages;

    # home-manager has a quirk redefining the profile location
    # to "/etc/profiles/per-user/${cfg.username}" if useUserPackages is on.
    # https://github.com/nix-community/home-manager/blob/0006da1381b87844c944fe8b925ec864ccf19348/modules/home-environment.nix#L414
    # Fortunately, it's not that hard to us to workaround with just a symlink.
    environment.etc = mkIf cfg.useUserPackages {
      "profiles/per-user/${config.user.userName}".source = "${config.user.home}/.nix-profile";
    };

  };
}
