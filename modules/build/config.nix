# Copyright (c) 2019-2024, see AUTHORS. Licensed under MIT License, see LICENSE.

{ config, lib, pkgs, ... }:

with lib;

{

  ###### interface

  options = {

    build = {
      initialBuild = mkOption {
        type = types.bool;
        default = false;
        internal = true;
        description = ''
          Whether this is the initial build for the bootstrap zip ball.
          Should not be enabled manually, see
          <filename>initial-build.nix</filename>.
        '';
      };

      installationDir = mkOption {
        type = types.path;
        internal = true;
        readOnly = true;
        description = "Path to installation directory.";
      };

      extraProotOptions = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Extra options passed to proot, e.g., extra bind mounts.";
      };

      # Fakechroot support options
      androidGlibc = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = "Android-patched glibc package for fakechroot login.";
      };

      androidFakechroot = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = "Android-patched fakechroot package.";
      };

      # Note: packAuditLib removed - path translation now built into ld.so

      bashInteractive = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = "Bash interactive package for login shell.";
      };

      patchPackageForAndroidGlibc = mkOption {
        type = types.nullOr (types.functionTo types.package);
        default = null;
        description = ''
          Function to patch a package for Android glibc compatibility.
          Takes a package and returns a patched package with rewritten
          interpreter and RPATH to use the Android glibc prefix.
          (Legacy: use replaceAndroidDependencies for better dependency handling)
        '';
      };

      replaceAndroidDependencies = mkOption {
        type = types.nullOr (types.functionTo types.package);
        default = null;
        description = ''
          Function to patch an entire derivation for Android glibc compatibility.
          Like NixOS replaceDependencies but uses patchelf (no path length constraint).
          Takes a derivation (e.g., buildEnv output) and returns a patched derivation
          with all ELF binaries and scripts rewritten for Android glibc.
          Applied to final environment.path for transitive dependency patching.
        '';
      };
    };

  };


  ###### implementation

  config = {

    build.installationDir = "/data/data/com.termux.nix/files/usr";

  };

}
