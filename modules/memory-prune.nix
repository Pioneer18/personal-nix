# modules/memory-prune.nix
#
# Weekly LaunchAgent that runs scripts/prune-memory.sh — the auto-curator for
# ~/.claude/projects/-Users-pioneer/memory/. Fires Sunday 03:00 local by default.
#
# Opt in by adding `./modules/memory-prune.nix` to the imports list in
# default.nix, then `dev` to rebuild. To change the schedule, edit the
# StartCalendarInterval list below.
#
# See modules/README.md for full usage, recovery, and dry-run instructions.
{ config, pkgs, lib, ... }:
{
  launchd.agents.memory-prune = {
    enable = true;
    config = {
      Label = "com.pioneer.memory-prune";
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "${config.home.homeDirectory}/projects/personal-nix/scripts/prune-memory.sh"
      ];

      # Weekly: Sunday (Weekday = 0) at 03:00 local.
      StartCalendarInterval = [{
        Weekday = 0;
        Hour = 3;
        Minute = 0;
      }];

      RunAtLoad = false;
      StandardOutPath = "/tmp/memory-prune.log";
      StandardErrorPath = "/tmp/memory-prune.log";

      # launchd does not source the shell init files, so we set PATH explicitly
      # to cover where claude, jq, and the nix-managed shell live.
      EnvironmentVariables = {
        PATH = lib.concatStringsSep ":" [
          "${config.home.homeDirectory}/.local/bin"
          "${config.home.homeDirectory}/.nix-profile/bin"
          "/etc/profiles/per-user/${config.home.username}/bin"
          "/run/current-system/sw/bin"
          "/nix/var/nix/profiles/default/bin"
          "/opt/homebrew/bin"
          "/usr/local/bin"
          "/usr/bin"
          "/bin"
        ];
        HOME = config.home.homeDirectory;
      };
    };
  };
}
