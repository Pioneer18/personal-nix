# modules/desk-push.nix
#
# Daily 18:00 commit + push of the personal /desk ledger (~/projects/desk)
# to its private GitHub remote. The /desk skill commits on every write; this
# only catches stragglers and pushes. Runs on /usr/bin/python3 (stdlib CLI).
#
# See ~/projects/personal-nix/wiki/decisions/desk-personal-ledger.md
{ config, ... }:
{
  launchd.agents.desk-push = {
    enable = true;
    config = {
      ProgramArguments = [
        "/usr/bin/python3"
        "${config.home.homeDirectory}/projects/personal-nix/skills/desk/bin/desk"
        "push"
      ];
      StartCalendarInterval = [{ Hour = 18; Minute = 0; }];
      RunAtLoad = false;
      StandardOutPath = "/tmp/desk-push.log";
      StandardErrorPath = "/tmp/desk-push.log";
    };
  };
}
