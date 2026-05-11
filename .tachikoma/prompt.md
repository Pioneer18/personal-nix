# Tachikoma — tachikoma-ui-nix-service

## Goal

Declare the Tachikoma UI as a launchd user agent in `personal-nix/default.nix` so it auto-starts on login and is always available at http://localhost:4000.

## Context

The Tachikoma UI Express server is at `mcps/tachikoma-ui/server/index.ts`. The frontend is already built by prior work. You are working in the personal-nix home-manager module.

### What already exists in default.nix

- `home.activation.symlinkPersonalSkills` — symlinks skills, runs after `writeBoundary`
- `home.activation.secretsFromKeychain` — regenerates `~/.secrets` from macOS Keychain, runs after `writeBoundary`

Both use `lib.hm.dag.entryAfter [ "writeBoundary" ]`. The `repoPath` let-binding is `"$HOME/projects/personal-nix"`.

### How launchd services work here

```nix
launchd.user.agents.my-service = {
  serviceConfig = {
    ProgramArguments = [ "/path/to/binary" "--flag" ];
    RunAtLoad = true;
    KeepAlive = true;
    StandardOutPath = "/tmp/my-service.log";
    StandardErrorPath = "/tmp/my-service.log";
  };
};
```

Node.js binary from nixpkgs: `${pkgs.nodejs_22}/bin/node`

### Secret: ANTHROPIC_API_KEY

`~/.secrets` is written by `secretsFromKeychain`. The launchd plist is generated at nix build time and cannot read `~/.secrets` directly. Solution: write a wrapper script at activation time that sources `~/.secrets` then execs the node server.

## Tasks

Work through these in order. Commit after each one passes its feedback loop.

### Task 1 — Add `home.activation.buildTachikomaUI`

Add to `default.nix` after `secretsFromKeychain`:

```nix
home.activation.buildTachikomaUI =
  lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    TACHIKOMA_UI="$HOME/projects/personal-nix/mcps/tachikoma-ui"
    if [ -d "$TACHIKOMA_UI" ]; then
      echo "personal-nix: building tachikoma-ui..."
      cd "$TACHIKOMA_UI"
      npm install --quiet 2>/dev/null || echo "personal-nix: npm install failed (non-fatal)"
      npm run build 2>/dev/null || echo "personal-nix: npm run build failed (non-fatal)"
    fi
  '';
```

Non-fatal on failure (so first rebuild before `dist/` exists doesn't break).

### Task 2 — Add `home.activation.writeTachikomaUILauncher`

Add after `buildTachikomaUI`. This writes the wrapper script that sources `~/.secrets` at runtime:

```nix
home.activation.writeTachikomaUILauncher =
  lib.hm.dag.entryAfter [ "writeBoundary" "buildTachikomaUI" ] ''
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/tachikoma-ui-start" << 'WRAPPER'
#!/bin/bash
set -a
[ -f "$HOME/.secrets" ] && . "$HOME/.secrets"
set +a
exec ${pkgs.nodejs_22}/bin/node --experimental-strip-types \
  "$HOME/projects/personal-nix/mcps/tachikoma-ui/server/index.ts"
WRAPPER
    chmod +x "$HOME/.local/bin/tachikoma-ui-start"
  '';
```

### Task 3 — Declare `launchd.user.agents.tachikoma-ui`

Add at the top level of the module (alongside `home.activation.*`):

```nix
launchd.user.agents.tachikoma-ui = {
  serviceConfig = {
    ProgramArguments = [ "${config.home.homeDirectory}/.local/bin/tachikoma-ui-start" ];
    RunAtLoad = true;
    KeepAlive = true;
    StandardOutPath = "/tmp/tachikoma-ui.log";
    StandardErrorPath = "/tmp/tachikoma-ui.log";
  };
};
```

### Task 4 — Verify nix eval exits without errors

Run the feedback loop. Fix any syntax or attribute errors until it exits cleanly.

## Feedback loops

```bash
cd ~/projects/personal-nix && nix eval --impure .#homeConfigurations 2>&1 | head -40
```

If the flake attribute path is wrong, try:
```bash
cd ~/projects/personal-nix && nix eval --impure .# 2>&1 | head -20
```

## Stop condition

When ALL of the following are true, emit `<promise>COMPLETE</promise>` and stop:

1. `default.nix` has `home.activation.buildTachikomaUI` that runs `npm install` and `npm run build` in `mcps/tachikoma-ui/`, non-fatal on failure
2. `default.nix` has `home.activation.writeTachikomaUILauncher` that writes and chmod-execs `~/.local/bin/tachikoma-ui-start`
3. The launcher script sources `~/.secrets` and execs `node --experimental-strip-types .../server/index.ts`
4. `default.nix` declares `launchd.user.agents.tachikoma-ui` with `RunAtLoad = true`, `KeepAlive = true`, and log paths at `/tmp/tachikoma-ui.log`
5. No secrets are hardcoded — the key is read at runtime from `~/.secrets`
6. `nix eval --impure .#homeConfigurations` exits without errors

## Quality bar

Prototype. Nix expressions must be syntactically valid. Activation steps must be non-fatal on first run.

## Important

- Only modify `default.nix`. Do not touch `mcp.nix`, `packages.nix`, `flake.nix`, `flake.lock`, or anything under `mcps/`.
- Commit after completing all tasks and passing the feedback loop.
- When done, emit exactly: `<promise>COMPLETE</promise>`
