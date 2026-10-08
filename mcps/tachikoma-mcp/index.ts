#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { execSync, spawn } from "child_process";
import { existsSync, readFileSync, writeFileSync, mkdirSync, readdirSync, chmodSync, statSync } from "fs";
import { join, basename, dirname } from "path";
import { homedir } from "os";

const HOME = homedir();
const PROJECTS_DIR = join(HOME, "projects");
const PERSONAL_NIX_DIR = join(PROJECTS_DIR, "personal-nix");
const WORK_REQUESTS_DIR = join(PERSONAL_NIX_DIR, "wiki", "work-requests");
const TACHIKOMA_SKILLS_DIR = join(HOME, ".claude", "skills", "tachikoma");
const TACHIKOMA_RUNTIME_DIR = join(HOME, ".tachikoma");
const SENTINEL = "<promise>COMPLETE</promise>";

// ── Types ────────────────────────────────────────────────────────────────────

interface TachikomaState {
  repo: string;
  branch: string;
  worktree: string;
  status: "running" | "complete" | "cap" | "error" | "stopped" | "unknown";
  pid: number | null;
  iter: string | null;
  lastProgress: string | null;
}

interface DrainWorker {
  id: number;
  logPath: string;
  logAgeSeconds: number;
  stateFileExists: boolean;
  likelyState: "halted-early" | "had-state" | "stale";
  lastLogTail: string | null;
}

interface WorkRequest {
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

// ── Parsing helpers ───────────────────────────────────────────────────────────

function expandHome(p: string): string {
  return p.startsWith("~/") ? join(HOME, p.slice(2)) : p;
}

function parseFrontmatter(content: string): { data: Record<string, string>; body: string } {
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

function parseSection(body: string, heading: string): string {
  const re = new RegExp(`## ${heading}\\n([\\s\\S]*?)(?=\\n## |$)`);
  return body.match(re)?.[1]?.trim() ?? "";
}

function parseBulletList(text: string): string[] {
  return text.split("\n")
    .filter(l => /^\s*[-*]\s/.test(l))
    .map(l => l.replace(/^\s*[-*]\s+/, "`").replace(/`$/, "").trim())
    .filter(Boolean);
}

// ── tachikoma_status ──────────────────────────────────────────────────────────────

function parseWorktrees(porcelain: string): Array<{ path: string; branch: string }> {
  return porcelain.trim().split("\n\n").flatMap(block => {
    const lines = block.split("\n");
    const path = lines.find(l => l.startsWith("worktree "))?.slice(9) ?? "";
    const branch = (lines.find(l => l.startsWith("branch ")) ?? "").replace("branch refs/heads/", "");
    return path ? [{ path, branch }] : [];
  });
}

function pidAlive(pid: number): boolean {
  try { process.kill(pid, 0); return true; } catch { return false; }
}

function readTachikomaState(wtPath: string): Pick<TachikomaState, "status" | "pid" | "iter" | "lastProgress"> {
  const r = join(wtPath, ".tachikoma");
  const pidFile = join(r, "run.pid");
  const outcomeFile = join(r, "outcome");
  const progressFile = join(r, "progress.txt");
  const logFile = join(r, "run.log");

  let status: TachikomaState["status"] = "unknown";
  let pid: number | null = null;

  if (existsSync(pidFile)) {
    const p = parseInt(readFileSync(pidFile, "utf8").trim());
    if (!isNaN(p) && pidAlive(p)) {
      pid = p; status = "running";
    } else {
      status = existsSync(outcomeFile)
        ? (readFileSync(outcomeFile, "utf8").trim() as TachikomaState["status"])
        : "unknown";
    }
  } else if (existsSync(outcomeFile)) {
    status = readFileSync(outcomeFile, "utf8").trim() as TachikomaState["status"];
  }

  let iter: string | null = null;
  if (existsSync(logFile)) {
    const matches = [...readFileSync(logFile, "utf8").matchAll(/─── iter (\d+) \/ (\d+)/g)];
    if (matches.length) {
      const m = matches[matches.length - 1];
      iter = `${m[1]}/${m[2]}`;
    }
  }

  let lastProgress: string | null = null;
  if (existsSync(progressFile)) {
    const lines = readFileSync(progressFile, "utf8")
      .split("\n").filter(l => l.trim() && !l.startsWith("##") && !l.startsWith("```"));
    if (lines.length) lastProgress = lines[lines.length - 1].replace(/^[-*]\s*/, "").trim();
  }

  return { status, pid, iter, lastProgress };
}

function detectDrainWorkers(): DrainWorker[] {
  if (!existsSync(TACHIKOMA_RUNTIME_DIR)) return [];
  const now = Date.now();
  const workers: DrainWorker[] = [];

  for (const entry of readdirSync(TACHIKOMA_RUNTIME_DIR)) {
    const m = entry.match(/^drain-worker-(\d+)\.log$/);
    if (!m) continue;
    const id = parseInt(m[1]);
    const logPath = join(TACHIKOMA_RUNTIME_DIR, entry);
    const stateFile = join(TACHIKOMA_RUNTIME_DIR, `queue-drain.state.${id}`);
    const stateFileExists = existsSync(stateFile);

    let logAgeSeconds = -1;
    let lastLogTail: string | null = null;
    try {
      const st = statSync(logPath);
      logAgeSeconds = Math.floor((now - st.mtimeMs) / 1000);
      const content = readFileSync(logPath, "utf8").trim();
      if (content) {
        const lines = content.split("\n");
        lastLogTail = lines.slice(-3).join(" / ").slice(0, 240);
      }
    } catch { /* ignore */ }

    // Heuristic: state file absent + log >5min old → worker halted before it could
    // grab a slice. State file present → worker progressed past auto-grab.
    // No state + log <5min old → recently spawned, possibly still alive.
    let likelyState: DrainWorker["likelyState"];
    if (stateFileExists) likelyState = "had-state";
    else if (logAgeSeconds > 300) likelyState = "halted-early";
    else likelyState = "stale";

    workers.push({ id, logPath, logAgeSeconds, stateFileExists, likelyState, lastLogTail });
  }

  return workers.sort((a, b) => a.id - b.id);
}

function tachikomaStatus(): TachikomaState[] {
  if (!existsSync(PROJECTS_DIR)) return [];

  const all = readdirSync(PROJECTS_DIR, { withFileTypes: true })
    .filter(e => e.isDirectory())
    .flatMap(entry => {
      const repoPath = join(PROJECTS_DIR, entry.name);
      try { execSync(`git -C "${repoPath}" rev-parse --git-dir`, { stdio: "ignore" }); }
      catch { return []; }

      let porcelain: string;
      try { porcelain = execSync(`git -C "${repoPath}" worktree list --porcelain`, { encoding: "utf8" }); }
      catch { return []; }

      return parseWorktrees(porcelain)
        .filter(wt => wt.branch.startsWith("tachikoma/") && existsSync(join(wt.path, ".tachikoma")))
        .map(wt => ({
          repo: entry.name,
          branch: wt.branch,
          worktree: wt.path,
          ...readTachikomaState(wt.path),
        }));
    });

  // Sibling worktrees share .git metadata, so iterating each PROJECTS_DIR
  // entry yields the same `worktree list --porcelain` output. Dedupe by
  // absolute worktree path; first observer wins.
  const seen = new Map<string, TachikomaState>();
  for (const state of all) {
    if (!seen.has(state.worktree)) seen.set(state.worktree, state);
  }
  return [...seen.values()];
}

// ── tachikoma_dispatch ────────────────────────────────────────────────────────────

function readWorkRequests(): WorkRequest[] {
  if (!existsSync(WORK_REQUESTS_DIR)) return [];

  return readdirSync(WORK_REQUESTS_DIR)
    .filter(f => f.endsWith(".md") && f !== ".gitkeep")
    .flatMap(file => {
      const filePath = join(WORK_REQUESTS_DIR, file);
      const content = readFileSync(filePath, "utf8");
      const { data, body } = parseFrontmatter(content);
      if (!data.status || !data.target_repo) return [];

      const qbRaw = parseSection(body, "Quality bar").split(/[\s—]/)[0].toLowerCase();
      const qb = ["prototype", "production", "library"].includes(qbRaw) ? qbRaw : "production";

      return [{
        slug: file.replace(".md", ""),
        filePath,
        status: data.status,
        targetRepo: expandHome(data.target_repo),
        priority: parseInt(data.priority ?? "100"),
        goal: parseSection(body, "Goal"),
        qualityBar: qb,
        filesInScope: parseBulletList(parseSection(body, "Files in scope")),
        filesOutOfScope: parseBulletList(parseSection(body, "Files out of scope")),
        stopCondition: parseSection(body, "Stop condition"),
        bodyLength: body.length,
      }];
    })
    .sort((a, b) => a.priority - b.priority || a.slug.localeCompare(b.slug));
}

function detectFeedbackLoops(repoPath: string): { typecheck: string; test: string; lint: string } {
  const pkgPath = join(repoPath, "package.json");
  if (existsSync(pkgPath)) {
    const scripts: Record<string, string> = JSON.parse(readFileSync(pkgPath, "utf8")).scripts ?? {};
    const tcKey = ["typecheck", "type-check", "tsc"].find(k => k in scripts) ?? null;
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
  return { typecheck: `echo "no typecheck"`, test: `echo "no tests"`, lint: `echo "no lint"` };
}

function buildAllowedTools(cmds: { typecheck: string; test: string; lint: string }): string {
  const bins = new Set(["echo", "grep"]);
  for (const cmd of Object.values(cmds)) {
    const first = cmd.trim().split(/\s+/)[0];
    if (first) bins.add(first);
  }
  return `Edit Write Read Glob Grep Bash(git *) ${[...bins].map(b => `Bash(${b} *)`).join(" ")}`;
}

const QUALITY_BARS: Record<string, string> = {
  prototype: "This is prototype code. Speed over perfection. Shortcuts and skipped edge cases are acceptable. Do NOT over-engineer.",
  production: "This codebase will outlive you. Every shortcut becomes someone else's burden. Every hack compounds into technical debt. Fight entropy. Production code requires tests, type safety, and explicit error handling.",
  library: "This is a public library API. Backward compatibility matters. Be careful with breaking changes — flag them explicitly in commit messages.",
};

function renderTemplate(tmpl: string, vars: Record<string, string>): string {
  return Object.entries(vars).reduce((s, [k, v]) => s.replaceAll(`{{${k}}}`, v), tmpl);
}

function parseTachikomaConf(): Record<string, string> {
  const confPath = join(HOME, ".claude", "tachikoma.conf");
  if (!existsSync(confPath)) return {};
  const conf: Record<string, string> = {};
  for (const line of readFileSync(confPath, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (trimmed.startsWith("#") || !trimmed.includes("=")) continue;
    const idx = trimmed.indexOf("=");
    conf[trimmed.slice(0, idx).trim()] = trimmed.slice(idx + 1).trim();
  }
  return conf;
}

function synthesizePrd(wr: WorkRequest): object {
  const numbered = wr.stopCondition.split("\n").filter(l => /^\d+\./.test(l.trim()));
  const items = numbered.length
    ? numbered.map((l, i) => ({
        id: `T-${String(i + 1).padStart(3, "0")}`,
        category: "functional",
        description: l.replace(/^\d+\.\s*\*{0,2}([^*—:]+)[\*—:].*/s, "$1").trim(),
        steps: [],
        blocked_by: [],
        passes: false,
      }))
    : [{ id: "T-001", category: "functional", description: wr.goal, steps: [], blocked_by: [], passes: false }];

  return {
    goal: wr.goal,
    quality_bar: wr.qualityBar,
    files_in_scope: wr.filesInScope,
    files_out_of_scope: wr.filesOutOfScope,
    stop_condition: wr.stopCondition,
    items,
  };
}

async function tachikomaDispatch(
  cap: number,
  slug?: string,
  targetRepoOverride?: string,
): Promise<object> {
  const requests = readWorkRequests();
  let next: WorkRequest | undefined;
  if (slug) {
    // Caller specified a slug — pick that work-request specifically. Don't
    // require status='open' (a 'grabbed' row with no live process is a
    // common stuck-state and the caller may want to retry).
    next = requests.find(r => r.slug === slug);
    if (!next) {
      throw new Error(
        `Work-request '${slug}' not found in ~/projects/personal-nix/wiki/work-requests/. ` +
        `Available slugs: ${requests.map(r => r.slug).slice(0, 10).join(", ")}${requests.length > 10 ? "..." : ""}`,
      );
    }
    if (next.status !== "open") {
      throw new Error(
        `Work-request '${slug}' has status '${next.status}'; expected 'open'. ` +
        `Resolve the prior dispatch (recall / complete / clean up worktree) before re-dispatching.`,
      );
    }
  } else {
    // No slug — default behavior: pick the highest-priority open + ready.
    next = requests.find(r => r.status === "open" && existsSync(r.targetRepo) && r.bodyLength > 50);
    if (!next) throw new Error("No open + ready work requests. Check ~/projects/personal-nix/wiki/work-requests/.");
  }
  if (targetRepoOverride) {
    // Caller-supplied target_repo overrides the work-request's declared
    // target. Lets the same brief drive different repos.
    next = { ...next, targetRepo: expandHome(targetRepoOverride) };
  }
  if (!existsSync(next.targetRepo)) {
    throw new Error(`Target repo does not exist on disk: ${next.targetRepo}`);
  }
  if (next.bodyLength <= 50) {
    throw new Error(`Work-request '${next.slug}' body is too small (${next.bodyLength} chars). Expand the spec before dispatching.`);
  }

  const repoName = basename(next.targetRepo);
  const branch = `tachikoma/${next.slug}`;
  const worktreePath = join(dirname(next.targetRepo), `${repoName}-tachikoma-${next.slug}`);

  // Collision checks
  try {
    execSync(`git -C "${next.targetRepo}" show-ref --verify --quiet "refs/heads/${branch}"`, { stdio: "ignore" });
    throw new Error(`Branch ${branch} already exists. Finish or clean up the prior run first.`);
  } catch (e: any) { if ((e as Error).message.includes("Branch")) throw e; }
  if (existsSync(worktreePath)) throw new Error(`Worktree path already exists: ${worktreePath}`);

  const baseBranch = execSync(`git -C "${next.targetRepo}" rev-parse --abbrev-ref HEAD`, { encoding: "utf8" }).trim();

  // Create worktree
  execSync(`git -C "${next.targetRepo}" worktree add "${worktreePath}" -b "${branch}" "${baseBranch}"`);

  // Scaffold .tachikoma/
  const tachikomaDir = join(worktreePath, ".tachikoma");
  mkdirSync(tachikomaDir, { recursive: true });
  writeFileSync(join(tachikomaDir, "base_branch"), baseBranch);

  // .gitignore
  const gitignorePath = join(worktreePath, ".gitignore");
  const existing = existsSync(gitignorePath) ? readFileSync(gitignorePath, "utf8") : "";
  if (!existing.includes(".tachikoma/")) writeFileSync(gitignorePath, existing.trimEnd() + "\n.tachikoma/\n");

  // Render templates
  const feedback = detectFeedbackLoops(next.targetRepo);
  const allowedTools = buildAllowedTools(feedback);
  const conf = parseTachikomaConf();
  const model = conf.model ?? "";
  const plannerModel = conf.planner_model ?? "";
  // TACHIKOMA-PROVIDER-BRIDGE: empty defaults to claude in the bash template.
  const provider = conf.provider ?? "";

  const tachikomaShPath = join(tachikomaDir, "tachikoma.sh");
  writeFileSync(tachikomaShPath, renderTemplate(
    readFileSync(join(TACHIKOMA_SKILLS_DIR, "tachikoma.sh.tmpl"), "utf8"),
    { REPO_PATH: worktreePath, SENTINEL, ALLOWED_TOOLS: allowedTools, MODEL: model, PLANNER_MODEL: plannerModel, PROVIDER: provider }
  ));
  chmodSync(tachikomaShPath, "755");

  writeFileSync(join(tachikomaDir, "prompt.md"), renderTemplate(
    readFileSync(join(TACHIKOMA_SKILLS_DIR, "prompt.md.tmpl"), "utf8"),
    {
      GOAL: next.goal,
      QUALITY_BAR_PARAGRAPH: QUALITY_BARS[next.qualityBar] ?? QUALITY_BARS.production,
      FILES_IN_SCOPE: next.filesInScope.join("\n"),
      FILES_OUT_OF_SCOPE: next.filesOutOfScope.join("\n"),
      STOP_CONDITION: next.stopCondition,
      TASK_SOURCE_BLOCK: "Read `plans/prd.json` for the backlog. Pick the highest-priority item where `passes` is `false` and all `blocked_by` items have `passes: true`. After implementing, set that item's `passes` to `true` in the same commit.",
      TYPECHECK_CMD: feedback.typecheck,
      TEST_CMD: feedback.test,
      LINT_CMD: feedback.lint,
      COMMIT_INSTRUCTIONS: "Commit message format:\n  <type>: <description> [T-NNN]\n\nWhere <type> is feat|fix|refactor|test|docs|chore. Include the PRD item id in brackets.",
      COMPLETION_INSTRUCTIONS: "If every item in `plans/prd.json` has `passes: true`:\n  1. `rm plans/prd.json`\n  2. `git add -A && git commit -m \"chore: tachikoma complete, remove plans/prd.json\"`\n  3. Output exactly: <promise>COMPLETE</promise>",
    }
  ));

  // Render .tachikoma/ship.md so the auto-ship path in tachikoma.sh fires on
  // <promise>COMPLETE</promise>. Without this the runtime check at
  // tachikoma.sh.tmpl:382 always falls through to "ship.md not found".
  const goalFirstLine = next.goal.split("\n")[0].trim().slice(0, 100);
  const prTitle = goalFirstLine || next.slug;
  writeFileSync(join(tachikomaDir, "ship.md"), renderTemplate(
    readFileSync(join(TACHIKOMA_SKILLS_DIR, "ship.md.tmpl"), "utf8"),
    {
      WORKTREE_PATH: worktreePath,
      TACHIKOMA_BRANCH: branch,
      BASE_BRANCH: baseBranch,
      PR_TARGET_BRANCH: baseBranch,
      SLUG: next.slug,
      REPO_OWNER_NAME: "",
      GITHUB_ISSUE_LINE: "",
      COMMIT_MESSAGE: `${prTitle} [${next.slug}]`,
      PR_TITLE: prTitle,
      ISSUE_LABEL_BLOCK: "",
      ISSUE_CLOSE_BLOCK: "",
    }
  ));

  // ship.md references .tachikoma/ship_body.txt via `gh pr create --body-file`.
  writeFileSync(
    join(tachikomaDir, "ship_body.txt"),
    `Tachikoma run for \`${next.slug}\`.\n\n${next.goal}\n`,
  );

  // Write PRD + commit scaffold
  const plansDir = join(worktreePath, "plans");
  mkdirSync(plansDir, { recursive: true });
  writeFileSync(join(plansDir, "prd.json"), JSON.stringify(synthesizePrd(next), null, 2));
  execSync(`git -C "${worktreePath}" add .gitignore plans/prd.json`);
  execSync(`git -C "${worktreePath}" commit -m "chore: scaffold tachikoma loop for ${next.slug}"`);

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

  return { slug: next.slug, branch, baseBranch, worktree: worktreePath, pid, cap, workRequest: next.slug };
}

// ── MCP Server ────────────────────────────────────────────────────────────────

const server = new Server(
  { name: "tachikoma-mcp", version: "0.1.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "tachikoma_status",
      description: "List Tachikoma worktrees across ~/projects/ (with status, PID liveness, iteration progress, last progress note) AND queue-drain workers detected via ~/.tachikoma/drain-worker-N.log files. Returns an object {worktrees, drainWorkers} so callers see drain workers even when they halted before any worktree was created.",
      inputSchema: { type: "object" as const, properties: {} },
    },
    {
      name: "tachikoma_dispatch",
      description: "Scaffold a tachikoma worktree and launch the AFK loop. Defaults to grabbing the next open + ready work-request from ~/projects/personal-nix/wiki/work-requests/; pass `slug` to dispatch a specific work-request instead. Returns PID, branch, and worktree path.",
      inputSchema: {
        type: "object" as const,
        properties: {
          cap: { type: "number", description: "Max AFK iterations (default: 5, max: 50)." },
          slug: { type: "string", description: "Optional. Specific work-request slug to dispatch (filename stem under wiki/work-requests/, e.g. 'proxy-19-outlook-msgraph-auth'). Without this, picks the highest-priority open + ready request." },
          target_repo: { type: "string", description: "Optional. Override the target_repo declared in the work-request frontmatter. Absolute path or ~ prefix. Useful for re-running the same brief against a different repo." },
        },
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "tachikoma_status") {
    const worktrees = tachikomaStatus();
    const drainWorkers = detectDrainWorkers();
    if (worktrees.length === 0 && drainWorkers.length === 0) {
      return {
        content: [{
          type: "text" as const,
          text: "No Tachikoma worktrees under ~/projects/ and no drain workers in ~/.tachikoma/.",
        }],
      };
    }
    return {
      content: [{
        type: "text" as const,
        text: JSON.stringify({ worktrees, drainWorkers }, null, 2),
      }],
    };
  }

  if (name === "tachikoma_dispatch") {
    try {
      const a = (args as Record<string, unknown>) ?? {};
      const rawCap = a.cap;
      const cap = typeof rawCap === "number" ? Math.min(Math.max(1, rawCap), 50) : 5;
      const slug = typeof a.slug === "string" && a.slug.trim().length > 0 ? a.slug.trim() : undefined;
      const targetRepo = typeof a.target_repo === "string" && a.target_repo.trim().length > 0 ? a.target_repo.trim() : undefined;
      const result = await tachikomaDispatch(cap, slug, targetRepo);
      return { content: [{ type: "text" as const, text: JSON.stringify(result, null, 2) }] };
    } catch (e: unknown) {
      return {
        content: [{ type: "text" as const, text: `Error: ${e instanceof Error ? e.message : String(e)}` }],
        isError: true,
      };
    }
  }

  return { content: [{ type: "text" as const, text: `Unknown tool: ${name}` }], isError: true };
});

const transport = new StdioServerTransport();
await server.connect(transport);
