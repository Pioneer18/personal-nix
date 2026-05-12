import { execSync, spawn } from "child_process";
import {
  existsSync,
  readFileSync,
  writeFileSync,
  unlinkSync,
  mkdirSync,
  readdirSync,
  chmodSync,
} from "fs";
import { join, basename, dirname } from "path";
import os from "os";

const HOME = os.homedir();
export const PROJECTS_DIR = join(HOME, "projects");
const PERSONAL_NIX_DIR = join(PROJECTS_DIR, "personal-nix");
const QUEUE_DRAIN_STATE_FILE = join(HOME, ".tachikoma", "queue-drain.state");
export const WORK_REQUESTS_DIR = join(PERSONAL_NIX_DIR, "wiki", "work-requests");
const TACHIKOMA_SKILLS_DIR = join(HOME, ".claude", "skills", "tachikoma");
export const SENTINEL = "<promise>COMPLETE</promise>";

const BMO_FACES = [
  "smile",
  "content",
  "neutral",
  "angry",
  "disbelief",
  "frustrated",
  "out-of-wack",
] as const;

export type BmoFace = (typeof BMO_FACES)[number];

export type TachikomaStatus =
  | "running"
  | "complete"
  | "cap"
  | "error"
  | "stopped"
  | "unknown"
  | "stale";

export interface TachikomaState {
  repo: string;
  branch: string;
  worktree: string;
  slug: string;
  status: TachikomaStatus;
  pid: number | null;
  iter: string | null;
  lastProgress: string | null;
  bmoFace: BmoFace;
}

export interface WorkRequest {
  slug: string;
  filePath: string;
  status: string;
  targetRepo: string;
  priority: number;
  goal: string;
  qualityBar: string;
  filesInScope: string[];
  filesOutOfScope: string[];
  stopCondition: string;
  bodyLength: number;
}

export interface WorkQueueItem {
  slug: string;
  status: "open" | "grabbed" | "done";
  targetRepo: string;
  priority: number;
  goal: string;
  qualityBar: string;
  activeBranch: string | null;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function slugHash(slug: string): number {
  return slug.split("").reduce((acc, c) => acc + c.charCodeAt(0), 0);
}

function assignBmoFace(slug: string, status: TachikomaStatus): BmoFace {
  const hash = slugHash(slug);
  if (status === "complete") return "smile";
  if (status === "stopped") return "neutral";
  if (status === "error" || status === "cap" || status === "stale") {
    const negatives: BmoFace[] = ["angry", "disbelief", "frustrated"];
    return negatives[Math.abs(hash) % negatives.length];
  }
  return BMO_FACES[Math.abs(hash) % BMO_FACES.length];
}

export function expandHome(p: string): string {
  return p.startsWith("~/") ? join(HOME, p.slice(2)) : p;
}

export function parseFrontmatter(content: string): {
  data: Record<string, string>;
  body: string;
} {
  const match = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) return { data: {}, body: content };
  const data: Record<string, string> = {};
  for (const line of match[1].split("\n")) {
    const idx = line.indexOf(":");
    if (idx === -1) continue;
    data[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
  }
  return { data, body: match[2] };
}

export function parseSection(body: string, heading: string): string {
  const re = new RegExp(`## ${heading}\\n([\\s\\S]*?)(?=\\n## |$)`);
  return body.match(re)?.[1]?.trim() ?? "";
}

export function parseBulletList(text: string): string[] {
  return text
    .split("\n")
    .filter((l) => /^\s*[-*]\s/.test(l))
    .map((l) =>
      l
        .replace(/^\s*[-*]\s+/, "`")
        .replace(/`$/, "")
        .trim()
    )
    .filter(Boolean);
}

// ── Worktree / status ─────────────────────────────────────────────────────────

function parseWorktrees(
  porcelain: string
): Array<{ path: string; branch: string }> {
  return porcelain
    .trim()
    .split("\n\n")
    .flatMap((block) => {
      const lines = block.split("\n");
      const path =
        lines.find((l) => l.startsWith("worktree "))?.slice(9) ?? "";
      const branch = (
        lines.find((l) => l.startsWith("branch ")) ?? ""
      ).replace("branch refs/heads/", "");
      return path ? [{ path, branch }] : [];
    });
}

function pidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function readTachikomaState(
  wtPath: string
): Pick<TachikomaState, "status" | "pid" | "iter" | "lastProgress"> {
  const r = join(wtPath, ".tachikoma");
  const pidFile = join(r, "run.pid");
  const outcomeFile = join(r, "outcome");
  const progressFile = join(r, "progress.txt");
  const logFile = join(r, "run.log");

  let status: TachikomaStatus = "unknown";
  let pid: number | null = null;

  if (existsSync(pidFile)) {
    const p = parseInt(readFileSync(pidFile, "utf8").trim());
    if (!isNaN(p) && pidAlive(p)) {
      pid = p;
      status = "running";
    } else {
      // pid file exists but process is dead → stale
      status = existsSync(outcomeFile)
        ? (readFileSync(outcomeFile, "utf8").trim() as TachikomaStatus)
        : "stale";
      if (!existsSync(outcomeFile)) {
        status = "stale";
      }
    }
  } else if (existsSync(outcomeFile)) {
    status = readFileSync(outcomeFile, "utf8").trim() as TachikomaStatus;
  }

  let iter: string | null = null;
  if (existsSync(logFile)) {
    const matches = [
      ...readFileSync(logFile, "utf8").matchAll(/─── iter (\d+) \/ (\d+)/g),
    ];
    if (matches.length) {
      const m = matches[matches.length - 1];
      iter = `${m[1]}/${m[2]}`;
    }
  }

  let lastProgress: string | null = null;
  if (existsSync(progressFile)) {
    const lines = readFileSync(progressFile, "utf8")
      .split("\n")
      .filter((l) => l.trim() && !l.startsWith("##") && !l.startsWith("```"));
    if (lines.length)
      lastProgress = lines[lines.length - 1]
        .replace(/^[-*]\s*/, "")
        .trim();
  }

  return { status, pid, iter, lastProgress };
}

export function tachikomaStatus(): TachikomaState[] {
  if (!existsSync(PROJECTS_DIR)) return [];

  const all = readdirSync(PROJECTS_DIR, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .flatMap((entry) => {
      const repoPath = join(PROJECTS_DIR, entry.name);
      try {
        execSync(`git -C "${repoPath}" rev-parse --git-dir`, {
          stdio: "ignore",
        });
      } catch {
        return [];
      }

      let porcelain: string;
      try {
        porcelain = execSync(
          `git -C "${repoPath}" worktree list --porcelain`,
          { encoding: "utf8" }
        );
      } catch {
        return [];
      }

      return parseWorktrees(porcelain)
        .filter(
          (wt) =>
            wt.branch.startsWith("tachikoma/") &&
            existsSync(join(wt.path, ".tachikoma"))
        )
        .map((wt) => {
          const slug = wt.branch.replace("tachikoma/", "");
          const partial = readTachikomaState(wt.path);
          return {
            repo: entry.name,
            branch: wt.branch,
            worktree: wt.path,
            slug,
            bmoFace: assignBmoFace(slug, partial.status),
            ...partial,
          };
        });
    });

  const seen = new Map<string, TachikomaState>();
  for (const state of all) {
    if (!seen.has(state.worktree)) seen.set(state.worktree, state);
  }
  return [...seen.values()];
}

// ── Work requests ─────────────────────────────────────────────────────────────

export function readWorkRequests(): WorkRequest[] {
  if (!existsSync(WORK_REQUESTS_DIR)) return [];

  return readdirSync(WORK_REQUESTS_DIR)
    .filter((f) => f.endsWith(".md") && f !== ".gitkeep")
    .flatMap((file) => {
      const filePath = join(WORK_REQUESTS_DIR, file);
      const content = readFileSync(filePath, "utf8");
      const { data, body } = parseFrontmatter(content);
      if (!data.status || !data.target_repo) return [];

      const qbRaw = parseSection(body, "Quality bar")
        .split(/[\s—]/)[0]
        .toLowerCase();
      const qb = ["prototype", "production", "library"].includes(qbRaw)
        ? qbRaw
        : "production";

      return [
        {
          slug: file.replace(".md", ""),
          filePath,
          status: data.status,
          targetRepo: expandHome(data.target_repo),
          priority: parseInt(data.priority ?? "100"),
          goal: parseSection(body, "Goal"),
          qualityBar: qb,
          filesInScope: parseBulletList(parseSection(body, "Files in scope")),
          filesOutOfScope: parseBulletList(
            parseSection(body, "Files out of scope")
          ),
          stopCondition: parseSection(body, "Stop condition"),
          bodyLength: body.length,
        },
      ];
    })
    .sort((a, b) => a.priority - b.priority || a.slug.localeCompare(b.slug));
}

// ── Boot reconciliation ───────────────────────────────────────────────────────

function getMainRepoPath(worktreePath: string): string {
  const gitCommonDir = execSync(
    `git -C "${worktreePath}" rev-parse --path-format=absolute --git-common-dir`,
    { encoding: "utf8", stdio: "pipe" }
  ).trim();
  return dirname(gitCommonDir);
}

// Uses `git cherry` to detect squash-merged commits. Returns true when all
// non-scaffold commits on `branch` have an equivalent patch in `baseBranch`.
function isWorkAlreadyApplied(
  worktreePath: string,
  branch: string,
  baseBranch: string
): boolean {
  try {
    const cherry = execSync(
      `git -C "${worktreePath}" cherry -v "${baseBranch}" "${branch}"`,
      { encoding: "utf8", stdio: "pipe" }
    ).trim();
    if (!cherry) return true;
    const lines = cherry.split("\n").filter(Boolean);
    const workLines = lines.filter((l) => !l.includes("scaffold tachikoma loop"));
    if (workLines.length === 0) return true;
    return workLines.every((l) => l.startsWith("-"));
  } catch {
    return false;
  }
}

function updateWorkRequestStatus(filePath: string, from: string, to: string): void {
  const today = new Date().toISOString().slice(0, 10);
  const content = readFileSync(filePath, "utf8");
  const updated = content
    .replace(`status: ${from}`, `status: ${to}`)
    .replace(/last_updated: \S+/, `last_updated: ${today}`);
  if (updated !== content) writeFileSync(filePath, updated);
}

export function reconcileOnBoot(): void {
  const log = (msg: string) => console.log(`[reconcile] ${msg}`);

  // 1. Clear stale queue-drain.state when no session is actually running.
  if (existsSync(QUEUE_DRAIN_STATE_FILE)) {
    try {
      const { data } = parseFrontmatter(readFileSync(QUEUE_DRAIN_STATE_FILE, "utf8"));
      const worktree = (data.current_worktree ?? "").trim();
      let alive = false;
      if (worktree) {
        const pidFile = join(worktree, ".tachikoma", "run.pid");
        if (existsSync(pidFile)) {
          const pid = parseInt(readFileSync(pidFile, "utf8").trim());
          if (!isNaN(pid)) alive = pidAlive(pid);
        }
      }
      if (!alive) {
        unlinkSync(QUEUE_DRAIN_STATE_FILE);
        log("Removed stale queue-drain.state (no live session)");
      }
    } catch {
      try { unlinkSync(QUEUE_DRAIN_STATE_FILE); } catch {}
      log("Removed unparseable queue-drain.state");
    }
  }

  // 2. For each complete worktree whose work-request is open/grabbed, check
  //    whether the work was already squash-merged into the base branch. If so,
  //    mark the work-request done and remove the worktree + branch.
  const worktrees = tachikomaStatus();
  const workRequests = readWorkRequests();

  for (const wt of worktrees) {
    if (wt.status !== "complete") continue;

    const wr = workRequests.find((r) => r.slug === wt.slug);
    if (!wr || (wr.status !== "open" && wr.status !== "grabbed")) continue;

    const baseBranchFile = join(wt.worktree, ".tachikoma", "base_branch");
    const baseBranch = existsSync(baseBranchFile)
      ? readFileSync(baseBranchFile, "utf8").trim()
      : "master";

    if (isWorkAlreadyApplied(wt.worktree, wt.branch, baseBranch)) {
      log(`${wt.slug}: work already on ${baseBranch} — marking done, cleaning up worktree`);
      try {
        updateWorkRequestStatus(wr.filePath, wr.status, "done");
      } catch (e) {
        log(`  Failed to update work-request: ${e instanceof Error ? e.message : String(e)}`);
      }
      try {
        const mainRepo = getMainRepoPath(wt.worktree);
        try {
          execSync(`git -C "${mainRepo}" worktree remove "${wt.worktree}"`, { stdio: "pipe" });
        } catch {
          execSync(`git -C "${mainRepo}" worktree remove --force "${wt.worktree}"`, { stdio: "pipe" });
        }
        execSync(`git -C "${mainRepo}" branch -D "${wt.branch}"`, { stdio: "pipe" });
        log(`  Cleaned: ${wt.branch}`);
      } catch (e) {
        log(`  Git cleanup failed: ${e instanceof Error ? e.message : String(e)}`);
      }
    } else {
      log(`${wt.slug}: complete, work not yet on ${baseBranch} — skip (needs /tachikoma done)`);
    }
  }

  // 3. Grabbed work-requests with no matching worktree → reset to open so they
  //    can be picked up again.
  const remaining = tachikomaStatus();
  for (const wr of workRequests) {
    if (wr.status !== "grabbed") continue;
    if (!remaining.some((wt) => wt.slug === wr.slug)) {
      log(`${wr.slug}: grabbed but no worktree — resetting to open`);
      try {
        updateWorkRequestStatus(wr.filePath, "grabbed", "open");
      } catch (e) {
        log(`  Failed to reset: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
  }
}

// ── Work request CRUD ─────────────────────────────────────────────────────────

export function createWorkRequest(opts: {
  slug: string;
  targetRepo: string;
  goal: string;
  stopCondition: string;
  qualityBar: string;
}): void {
  const filePath = join(WORK_REQUESTS_DIR, `${opts.slug}.md`);
  if (existsSync(filePath)) throw new Error(`Work request already exists: ${opts.slug}`);
  const today = new Date().toISOString().slice(0, 10);
  const content = `---
status: open
target_repo: ${opts.targetRepo}
github_issue: ""
failure_count: 0
last_updated: ${today}
---

# ${opts.slug}

## Goal

${opts.goal}

## Stop condition

${opts.stopCondition}

## Quality bar

${opts.qualityBar}
`;
  mkdirSync(WORK_REQUESTS_DIR, { recursive: true });
  writeFileSync(filePath, content);
}

export function deleteWorkRequest(slug: string): void {
  const filePath = join(WORK_REQUESTS_DIR, `${slug}.md`);
  if (!existsSync(filePath)) throw new Error(`Work request not found: ${slug}`);
  const content = readFileSync(filePath, "utf8");
  const { data } = parseFrontmatter(content);
  if (data.status !== "done") throw new Error(`Can only delete done work requests (status: ${data.status})`);
  unlinkSync(filePath);
}

// ── Dispatch ──────────────────────────────────────────────────────────────────

const QUALITY_BARS: Record<string, string> = {
  prototype:
    "This is prototype code. Speed over perfection. Shortcuts and skipped edge cases are acceptable. Do NOT over-engineer.",
  production:
    "This codebase will outlive you. Every shortcut becomes someone else's burden. Every hack compounds into technical debt. Fight entropy. Production code requires tests, type safety, and explicit error handling.",
  library:
    "This is a public library API. Backward compatibility matters. Be careful with breaking changes — flag them explicitly in commit messages.",
};

function renderTemplate(
  tmpl: string,
  vars: Record<string, string>
): string {
  return Object.entries(vars).reduce(
    (s, [k, v]) => s.replaceAll(`{{${k}}}`, v),
    tmpl
  );
}

function synthesizePrd(wr: WorkRequest): object {
  const numbered = wr.stopCondition
    .split("\n")
    .filter((l) => /^\d+\./.test(l.trim()));
  const items = numbered.length
    ? numbered.map((l, i) => ({
        id: `T-${String(i + 1).padStart(3, "0")}`,
        category: "functional",
        description: l
          .replace(/^\d+\.\s*\*{0,2}([^*—:]+)[\*—:].*/s, "$1")
          .trim(),
        steps: [],
        blocked_by: [],
        passes: false,
      }))
    : [
        {
          id: "T-001",
          category: "functional",
          description: wr.goal,
          steps: [],
          blocked_by: [],
          passes: false,
        },
      ];

  return {
    goal: wr.goal,
    quality_bar: wr.qualityBar,
    files_in_scope: wr.filesInScope,
    files_out_of_scope: wr.filesOutOfScope,
    stop_condition: wr.stopCondition,
    items,
  };
}

function detectFeedbackLoops(
  repoPath: string
): { typecheck: string; test: string; lint: string } {
  const pkgPath = join(repoPath, "package.json");
  if (existsSync(pkgPath)) {
    const scripts: Record<string, string> =
      JSON.parse(readFileSync(pkgPath, "utf8")).scripts ?? {};
    const tcKey =
      ["typecheck", "type-check", "tsc"].find((k) => k in scripts) ?? null;
    return {
      typecheck: tcKey ? `npm run ${tcKey}` : `echo "no typecheck"`,
      test: "test" in scripts ? "npm test" : `echo "no tests"`,
      lint: "lint" in scripts ? "npm run lint" : `echo "no lint"`,
    };
  }
  const mkPath = join(repoPath, "Makefile");
  if (existsSync(mkPath)) {
    const mk = readFileSync(mkPath, "utf8");
    return {
      typecheck: /^typecheck:/m.test(mk) ? "make typecheck" : `echo "no typecheck"`,
      test: /^test:/m.test(mk) ? "make test" : `echo "no tests"`,
      lint: /^lint:/m.test(mk) ? "make lint" : `echo "no lint"`,
    };
  }
  return {
    typecheck: `echo "no typecheck"`,
    test: `echo "no tests"`,
    lint: `echo "no lint"`,
  };
}

function buildAllowedTools(cmds: {
  typecheck: string;
  test: string;
  lint: string;
}): string {
  const bins = new Set(["echo", "grep"]);
  for (const cmd of Object.values(cmds)) {
    const first = cmd.trim().split(/\s+/)[0];
    if (first) bins.add(first);
  }
  return `Edit Write Read Glob Grep Bash(git *) ${[...bins].map((b) => `Bash(${b} *)`).join(" ")}`;
}

export async function tachikomaDispatch(cap: number): Promise<object> {
  const requests = readWorkRequests();
  const next = requests.find(
    (r) =>
      r.status === "open" &&
      existsSync(r.targetRepo) &&
      r.bodyLength > 50
  );
  if (!next)
    throw new Error(
      "No open + ready work requests. Check ~/projects/personal-nix/wiki/work-requests/."
    );

  const repoName = basename(next.targetRepo);
  const branch = `tachikoma/${next.slug}`;
  const worktreePath = join(
    dirname(next.targetRepo),
    `${repoName}-tachikoma-${next.slug}`
  );

  // Collision checks
  try {
    execSync(
      `git -C "${next.targetRepo}" show-ref --verify --quiet "refs/heads/${branch}"`,
      { stdio: "ignore" }
    );
    throw new Error(
      `Branch ${branch} already exists. Finish or clean up the prior run first.`
    );
  } catch (e) {
    if (e instanceof Error && e.message.includes("Branch")) throw e;
  }
  if (existsSync(worktreePath))
    throw new Error(`Worktree path already exists: ${worktreePath}`);

  const baseBranch = execSync(
    `git -C "${next.targetRepo}" rev-parse --abbrev-ref HEAD`,
    { encoding: "utf8" }
  ).trim();

  // Create worktree
  execSync(
    `git -C "${next.targetRepo}" worktree add "${worktreePath}" -b "${branch}" "${baseBranch}"`
  );

  // Scaffold .tachikoma/
  const tachikomaDir = join(worktreePath, ".tachikoma");
  mkdirSync(tachikomaDir, { recursive: true });
  writeFileSync(join(tachikomaDir, "base_branch"), baseBranch);

  // .gitignore
  const gitignorePath = join(worktreePath, ".gitignore");
  const existing = existsSync(gitignorePath)
    ? readFileSync(gitignorePath, "utf8")
    : "";
  if (!existing.includes(".tachikoma/"))
    writeFileSync(gitignorePath, existing.trimEnd() + "\n.tachikoma/\n");

  // Render templates
  const feedback = detectFeedbackLoops(next.targetRepo);
  const allowedTools = buildAllowedTools(feedback);

  const tachikomaShPath = join(tachikomaDir, "tachikoma.sh");
  writeFileSync(
    tachikomaShPath,
    renderTemplate(
      readFileSync(
        join(TACHIKOMA_SKILLS_DIR, "tachikoma.sh.tmpl"),
        "utf8"
      ),
      {
        REPO_PATH: worktreePath,
        SENTINEL,
        ALLOWED_TOOLS: allowedTools,
      }
    )
  );
  chmodSync(tachikomaShPath, "755");

  writeFileSync(
    join(tachikomaDir, "prompt.md"),
    renderTemplate(
      readFileSync(
        join(TACHIKOMA_SKILLS_DIR, "prompt.md.tmpl"),
        "utf8"
      ),
      {
        GOAL: next.goal,
        QUALITY_BAR_PARAGRAPH:
          QUALITY_BARS[next.qualityBar] ?? QUALITY_BARS.production,
        FILES_IN_SCOPE: next.filesInScope.join("\n"),
        FILES_OUT_OF_SCOPE: next.filesOutOfScope.join("\n"),
        STOP_CONDITION: next.stopCondition,
        TASK_SOURCE_BLOCK:
          "Read `plans/prd.json` for the backlog. Pick the highest-priority item where `passes` is `false` and all `blocked_by` items have `passes: true`. After implementing, set that item's `passes` to `true` in the same commit.",
        TYPECHECK_CMD: feedback.typecheck,
        TEST_CMD: feedback.test,
        LINT_CMD: feedback.lint,
        COMMIT_INSTRUCTIONS:
          "Commit message format:\n  <type>: <description> [T-NNN]\n\nWhere <type> is feat|fix|refactor|test|docs|chore. Include the PRD item id in brackets.",
        COMPLETION_INSTRUCTIONS:
          "If every item in `plans/prd.json` has `passes: true`:\n  1. `rm plans/prd.json`\n  2. `git add -A && git commit -m \"chore: tachikoma complete, remove plans/prd.json\"`\n  3. Output exactly: <promise>COMPLETE</promise>",
      }
    )
  );

  // Write PRD + commit scaffold
  const plansDir = join(worktreePath, "plans");
  mkdirSync(plansDir, { recursive: true });
  writeFileSync(
    join(plansDir, "prd.json"),
    JSON.stringify(synthesizePrd(next), null, 2)
  );
  execSync(`git -C "${worktreePath}" add .gitignore plans/prd.json`);
  execSync(
    `git -C "${worktreePath}" commit -m "chore: scaffold tachikoma loop for ${next.slug}"`
  );

  // Mark work-request grabbed
  const content = readFileSync(next.filePath, "utf8");
  writeFileSync(next.filePath, content.replace("status: open", "status: grabbed"));

  // Launch detached AFK loop
  const child = spawn(tachikomaShPath, ["--afk", String(cap)], {
    detached: true,
    stdio: "ignore",
    cwd: worktreePath,
  });
  const pid = child.pid ?? 0;
  child.unref();

  return {
    slug: next.slug,
    branch,
    baseBranch,
    worktree: worktreePath,
    pid,
    cap,
    workRequest: next.slug,
  };
}
