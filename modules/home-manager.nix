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
          if nix-env -q | grep '^home-manager-path$'; then
            $DRY_RUN_CMD nix-env $VERBOSE_ARG --set-flag priority 120 home-manager-path
          fi
        '';
      };

      activationAfter = {
        homeManager = concatStringsSep " " (
          optional
            (cfg.backupFileExtension != null)
            "HOME_MANAGER_BACKUP_EXT='${cfg.backupFileExtension}'"
          ++ [ "${cfg.config.home.activationPackage}/activate" ]
        );
      } // optionalAttrs (config.build.absoluteStorePrefix != null) {
        # Rewrite home-manager symlinks to use absolute store prefix
        rewriteHomeManagerSymlinks = ''
          noteEcho "Rewriting home-manager symlinks to use absolute paths"
          prefix="${config.build.absoluteStorePrefix}"
          
          # Rewrite symlinks in home directory (top level only)
          # This includes both /nix/store/* and /nix/var/* symlinks (like .nix-profile)
          find "$HOME" -maxdepth 1 -type l 2>/dev/null | while read -r link; do
            target=$(readlink "$link")
            if [[ "$target" == /nix/store/* ]] || [[ "$target" == /nix/var/* ]]; then
              $VERBOSE_ECHO "Rewriting: $link"
              $DRY_RUN_CMD rm "$link"
              $DRY_RUN_CMD ln -s "$prefix$target" "$link"
            fi
          done || true
          
          # Rewrite symlinks in .config
          if [[ -d "$HOME/.config" ]]; then
            find "$HOME/.config" -type l 2>/dev/null | while read -r link; do
              target=$(readlink "$link")
              if [[ "$target" == /nix/store/* ]]; then
                $VERBOSE_ECHO "Rewriting: $link"
                $DRY_RUN_CMD rm "$link"
                $DRY_RUN_CMD ln -s "$prefix$target" "$link"
              fi
            done || true
          fi
          
          # Rewrite symlinks in .local, but exclude gcroots (managed by nix-store)
          if [[ -d "$HOME/.local" ]]; then
            find "$HOME/.local" -type l -not -path "*/gcroots/*" 2>/dev/null | while read -r link; do
              target=$(readlink "$link")
              if [[ "$target" == /nix/store/* ]]; then
                $VERBOSE_ECHO "Rewriting: $link"
                $DRY_RUN_CMD rm "$link"
                $DRY_RUN_CMD ln -s "$prefix$target" "$link"
              fi
            done || true
          fi
          
          # Rewrite per-user profile symlinks
          find /nix/var/nix/profiles/per-user -type l 2>/dev/null | while read -r link; do
            target=$(readlink "$link")
            if [[ "$target" == /nix/store/* ]]; then
              $VERBOSE_ECHO "Rewriting profile: $link"
              $DRY_RUN_CMD rm "$link"
              $DRY_RUN_CMD ln -s "$prefix$target" "$link"
            fi
          done || true
          
          # Rewrite nix-on-droid profile symlinks
          for link in /nix/var/nix/profiles/nix-on-droid /nix/var/nix/profiles/nix-on-droid-*-link; do
            if [[ -L "$link" ]]; then
              target=$(readlink "$link")
              if [[ "$target" == /nix/store/* ]]; then
                $VERBOSE_ECHO "Rewriting: $link"
                $DRY_RUN_CMD rm "$link"
                $DRY_RUN_CMD ln -s "$prefix$target" "$link"
              fi
            fi
          done || true
        '';
      };
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
