# Copyright (c) 2019-2022, see AUTHORS. Licensed under MIT License, see LICENSE.

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.environment;
  buildCfg = config.build;

  # Patch all packages for Android glibc if patchPackageForAndroidGlibc is set
  # Skip packages that have passthru.skipAndroidGlibcPatch = true (e.g., Go binaries)
  patchPkg = pkg:
    if buildCfg.patchPackageForAndroidGlibc != null
       && !(pkg.passthru.skipAndroidGlibcPatch or false)
    then buildCfg.patchPackageForAndroidGlibc pkg
    else pkg;

  # Apply patching to all packages
  patchedPackages = map patchPkg cfg.packages;

  # Build the base environment with all packages (unpatched)
  baseEnv = pkgs.buildEnv {
    name = "nix-on-droid-path";
    paths = cfg.packages;
    inherit (cfg) extraOutputsToInstall;
    meta = {
      description = "Environment of packages installed through Nix-on-Droid.";
    };
  };

  # Option 1: Per-package patching (current default)
  # Option 2: Environment-level patching with replaceAndroidDependencies
  patchedEnv =
    if buildCfg.replaceAndroidDependencies != null
    then buildCfg.replaceAndroidDependencies baseEnv
    else if buildCfg.patchPackageForAndroidGlibc != null
    then pkgs.buildEnv {
      name = "nix-on-droid-path";
      paths = patchedPackages;
      inherit (cfg) extraOutputsToInstall;
      meta = {
        description = "Environment of packages installed through Nix-on-Droid.";
      };
    }
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
        pkgs_to_remove=""
        for pkg_prefix in nix-on-droid-path nix-on-droid-path-android; do
          # Find all packages starting with this prefix (handles -1, -2, etc. suffixes)
          for full_name in $($nix_previous profile list 2>/dev/null | grep "^Name:" | sed 's/^Name:[[:space:]]*//'); do
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
