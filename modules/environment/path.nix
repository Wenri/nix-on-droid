# Copyright (c) 2019-2022, see AUTHORS. Licensed under MIT License, see LICENSE.

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.environment;
  buildCfg = config.build;

  # Build the base environment with all packages (unpatched)
  baseEnv = pkgs.buildEnv {
    name = "nix-on-droid-path";
    paths = cfg.packages;
    inherit (cfg) extraOutputsToInstall;
    meta = {
      description = "Environment of packages installed through Nix-on-Droid.";
    };
  };

  # Environment-level patching with replaceAndroidDependencies
  # Patches entire environment at once for Android glibc compatibility
  patchedEnv =
    if buildCfg.replaceAndroidDependencies != null
    then buildCfg.replaceAndroidDependencies baseEnv
    else baseEnv;
in

{

  ###### interface

  options = {

    environment = {
      packages = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "List of packages to be installed as user packages.";
      };

      path = mkOption {
        type = types.package;
        readOnly = true;
        internal = true;
        description = "Derivation for installing user packages.";
      };

      extraOutputsToInstall = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "doc" "info" "devdoc" ];
        description = "List of additional package outputs to be installed as user packages.";
      };
    };

  };


  ###### implementation

  config = {

    build.activation.installPackages = ''
      if [[ -e "${config.user.home}/.nix-profile/manifest.json" ]]; then
        # manual removal and installation as two non-atomical steps is required
        # because of https://github.com/NixOS/nix/issues/6349

        nix_previous="$(command -v nix)"

        # Remove nix-on-droid-path and nix-on-droid-path-android packages
        # Package names may have numeric suffixes (e.g., nix-on-droid-path-android-1)
        # Collect all matching names first to avoid issues with profile renumbering
        # Note: Strip ANSI color codes from nix profile list output
        pkgs_to_remove=""
        for pkg_prefix in nix-on-droid-path nix-on-droid-path-android; do
          # Find all packages starting with this prefix (handles -1, -2, etc. suffixes)
          # Use sed to strip ANSI escape codes (e.g., [1m, [0m) from colored output
          for full_name in $($nix_previous profile list 2>/dev/null | sed 's/\x1B\[[0-9;]*m//g' | grep "^Name:" | sed 's/^Name:[[:space:]]*//'); do
            # Check if the name starts with our prefix
            # e.g., nix-on-droid-path-android-1 matches nix-on-droid-path-android
            if [[ "$full_name" == "$pkg_prefix" || "$full_name" == "$pkg_prefix"-[0-9]* ]]; then
              pkgs_to_remove="$pkgs_to_remove $full_name"
            fi
          done
        done

        # Remove all matching packages in one command (if any found)
        if [[ -n "$pkgs_to_remove" ]]; then
          $DRY_RUN_CMD $nix_previous profile remove $pkgs_to_remove $VERBOSE_ARG || true
        fi

        # Only install if not already present (check by store path)
        target_path="${cfg.path}"
        if ! $nix_previous profile list 2>/dev/null | grep -qF "$target_path"; then
          $DRY_RUN_CMD $nix_previous profile install ${cfg.path}
        fi

        unset nix_previous pkgs_to_remove
      else
        $DRY_RUN_CMD nix-env --install ${cfg.path}
      fi
    '';

    environment = {
      packages = [
        (pkgs.callPackage ../../nix-on-droid { nix = config.nix.package; })
        pkgs.bashInteractive
        pkgs.cacert
        pkgs.coreutils
        pkgs.less # since nix tools really want a pager available, #27
        config.nix.package
      ];

      # Use patched environment when replaceAndroidDependencies is configured
      path = patchedEnv;
    };

  };

}
