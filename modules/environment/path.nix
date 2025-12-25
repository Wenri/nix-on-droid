# Copyright (c) 2019-2022, see AUTHORS. Licensed under MIT License, see LICENSE.

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.environment;
  buildCfg = config.build;
  
  storePrefix = if buildCfg.absoluteStorePrefix != null
    then buildCfg.absoluteStorePrefix
    else "";
  
  # Patch all packages for Android glibc if patchPackageForAndroidGlibc is set
  patchPkg = pkg:
    if buildCfg.patchPackageForAndroidGlibc != null
    then buildCfg.patchPackageForAndroidGlibc pkg
    else pkg;
  
  # Apply patching to all packages
  patchedPackages = map patchPkg cfg.packages;
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

    build.activation.installPackages = let
      prefix = if config.build.absoluteStorePrefix != null
        then config.build.absoluteStorePrefix
        else "";
    in ''
      if [[ -e "${config.user.home}/.nix-profile/manifest.json" ]]; then
        # manual removal and installation as two non-atomical steps is required
        # because of https://github.com/NixOS/nix/issues/6349

        nix_previous="$(command -v nix)"

        nix profile list \
          | grep 'nix-on-droid-path$' \
          | cut -d ' ' -f 4 \
          | xargs -t $DRY_RUN_CMD nix profile remove $VERBOSE_ARG

        $DRY_RUN_CMD $nix_previous profile install ${cfg.path}

        unset nix_previous
      else
        $DRY_RUN_CMD nix-env --install ${cfg.path}
      fi
      
      ${optionalString (prefix != "") ''
        # Rewrite symlinks inside the user-environment to use absolute paths
        # Get the actual store path of the user-environment (not our shadow copy)
        fixed_env="${config.user.home}/.local/share/nix-on-droid/user-environment"
        
        # Find the real user-environment in the store by following nix-env's profile links
        # Get the highest numbered profile-N-link
        latest_gen=$(ls /nix/var/nix/profiles/per-user/nix-on-droid/ 2>/dev/null | grep -E '^profile-[0-9]+-link$' | sort -t- -k2 -n | tail -1)
        if [[ -n "$latest_gen" ]]; then
          userenv=$(readlink "/nix/var/nix/profiles/per-user/nix-on-droid/$latest_gen")
          # Ensure it's a store path (add prefix if needed)
          if [[ "$userenv" == /nix/store/* ]]; then
            userenv="${prefix}$userenv"
          fi
        else
          userenv=""
        fi
        
        if [[ -n "$userenv" && -d "$userenv" ]]; then
          noteEcho "Rewriting user-environment symlinks for outside-proot access"
          noteEcho "Source: $userenv"
          
          mkdir -p "$(dirname "$fixed_env")"
          rm -rf "$fixed_env"
          mkdir -p "$fixed_env"
          
          # Function to fully resolve a symlink chain and rewrite all /nix/store refs
          resolve_and_rewrite() {
            local target="$1"
            local max_depth=10
            local depth=0
            
            while [[ $depth -lt $max_depth ]]; do
              if [[ "$target" == /nix/store/* ]]; then
                target="${prefix}$target"
              fi
              
              if [[ -L "$target" ]]; then
                local next=$(readlink "$target")
                if [[ "$next" == /nix/store/* ]]; then
                  target="${prefix}$next"
                  ((depth++))
                else
                  # Non-store symlink, we're done
                  break
                fi
              else
                # Not a symlink, we're done
                break
              fi
            done
            
            echo "$target"
          }
          
          # Check if a path or its symlink targets contain /nix/store references
          has_store_refs() {
            local path="$1"
            local max_check=5
            local checked=0
            
            while [[ $checked -lt $max_check && -L "$path" ]]; do
              local target=$(readlink "$path")
              if [[ "$target" == /nix/store/* ]]; then
                return 0  # Found a /nix/store reference
              fi
              if [[ "$target" == /* ]]; then
                path="$target"
              else
                path="$(dirname "$path")/$target"
              fi
              ((checked++))
            done
            return 1  # No /nix/store reference found
          }
          
          # Recursive function to create shadow structure with rewritten symlinks
          rewrite_tree() {
            local src="$1"
            local dst="$2"
            local depth="$3"
            
            if [[ $depth -gt 15 ]]; then
              return
            fi
            
            for item in "$src"/*; do
              [[ -e "$item" || -L "$item" ]] || continue
              local name=$(basename "$item")
              
              if [[ -L "$item" ]]; then
                local target=$(readlink "$item")
                if [[ "$target" == /nix/store/* ]]; then
                  # Resolve the full chain
                  local final_target=$(resolve_and_rewrite "$target")
                  
                  if [[ -d "$final_target" ]]; then
                    # Always recurse into directories to handle nested symlinks
                    mkdir -p "$dst/$name"
                    rewrite_tree "$final_target" "$dst/$name" $((depth + 1))
                  else
                    # File - link to fully resolved path
                    ln -s "$final_target" "$dst/$name"
                  fi
                elif [[ "$target" == /* ]]; then
                  # Absolute non-store symlink - check if it has store refs
                  if has_store_refs "$target"; then
                    local final_target=$(resolve_and_rewrite "$target")
                    if [[ -d "$final_target" ]]; then
                      mkdir -p "$dst/$name"
                      rewrite_tree "$final_target" "$dst/$name" $((depth + 1))
                    else
                      ln -s "$final_target" "$dst/$name"
                    fi
                  else
                    ln -s "$target" "$dst/$name"
                  fi
                else
                  ln -s "$target" "$dst/$name"
                fi
              elif [[ -d "$item" ]]; then
                mkdir -p "$dst/$name"
                rewrite_tree "$item" "$dst/$name" $((depth + 1))
              else
                ln -s "${prefix}$item" "$dst/$name"
              fi
            done
          }
          
          rewrite_tree "$userenv" "$fixed_env" 0
          
          # Update the profile to point to our fixed environment
          rm -f "/nix/var/nix/profiles/per-user/nix-on-droid/profile"
          ln -s "$fixed_env" "/nix/var/nix/profiles/per-user/nix-on-droid/profile"
        fi
      ''}
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

      path = pkgs.buildEnv {
        name = "nix-on-droid-path";

        # Use patched packages when patchPackageForAndroidGlibc is configured
        paths = patchedPackages;

        inherit (cfg) extraOutputsToInstall;

        meta = {
          description = "Environment of packages installed through Nix-on-Droid.";
        };
        
        # Rewrite symlinks to use absolute store prefix
        postBuild = optionalString (storePrefix != "") ''
          # Find and rewrite all symlinks pointing to /nix/store
          find $out -type l | while read -r link; do
            target=$(readlink "$link")
            if [[ "$target" == /nix/store/* ]]; then
              rm "$link"
              ln -s "${storePrefix}$target" "$link"
            fi
          done
        '';
      };
    };

  };

}
