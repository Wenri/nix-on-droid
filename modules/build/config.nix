# Copyright (c) 2019-2024, see AUTHORS. Licensed under MIT License, see LICENSE.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
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
        default = [];
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
        description = "Patched environment containing bash for login shell.";
      };

      replaceAndroidDependencies = mkOption {
        type = types.functionTo (types.functionTo types.attrs);
        description = ''
          Function to patch an entire derivation for Android glibc compatibility.
          Like NixOS replaceDependencies but uses patchelf (no path length constraint).
          Takes a derivation and options, returns { out = patched-drv; memo = {...}; getPkg = fn; }.
          Applied to final environment.path for transitive dependency patching.
        '';
      };

      patchedPkgs = mkOption {
        type = types.attrs;
        readOnly = true;
        description = ''
          pkgs with all packages mapped through replaceAndroidDependencies memo.
          Use this for runtime packages that need Android patching.
          Packages in the memo return their patched version; others return original.
        '';
      };

      symlinkManifest = mkOption {
        type = types.listOf (types.attrsOf types.str);
        readOnly = true;
        description = ''
          List of { symlinkPath, targetPath } entries.  The activation
          wrapper (nix-on-droid.sh) installs kernel-visible symlinks
          under /data/data/com.termux.nix/nix/ that patched binaries
          reference at runtime (byte-substituted from /nix/store/*).
          Enables static ELFs to resolve store paths without libc
          preload interception.  Emitted as $out/symlink-manifest in
          the activationPackage.
        '';
      };
    };
  };

  ###### implementation

  config = {
    # Canonical source of truth for nix-on-droid installation directory
    # Other modules should use config.build.installationDir
    build.installationDir = "/data/data/com.termux.nix/files/usr";
  };
}
