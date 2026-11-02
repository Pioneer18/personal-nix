# modules/group-portal-bug-scan.nix
#
# Daily 07:00 headless Claude Code scan of the Group Portal prod logs. It may
# open fix PRs (fix/scan-*); it never merges, deploys, or reads the prod DB.
# launchd runs a missed slot once on wake. Log: ~/Library/Logs/group-portal-bug-scan/.
#
# See ~/projects/personal-nix/wiki/recipes/group-portal-bug-scan.md
{ config, ... }:
{
  launchd.agents.group-portal-bug-scan = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/zsh"
        "${config.home.homeDirectory}/projects/personal-nix/scripts/group-portal-bug-scan.sh"
      ];
      StartCalendarInterval = [{ Hour = 7; Minute = 0; }];
      RunAtLoad = false;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/group-portal-bug-scan/launchd.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/group-portal-bug-scan/launchd.log";
    };
  };
}
