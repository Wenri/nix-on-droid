# Copyright (c) 2019-2026, see AUTHORS. Licensed under MIT License, see LICENSE.
[
  (import ./typespeed.nix)
  # Expose installationDir as a pkgs attr so android-only package overlays
  # in downstream flakes (e.g. claude-code path translation) can read
  # `final.installationDir` without threading. Must stay in sync with
  # modules/build/config.nix build.installationDir.
  (_final: _prev: {
    installationDir = "/data/data/com.termux.nix/files/usr";
  })
]
