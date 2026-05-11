#!/usr/bin/env node
import express from "express";
import cors from "cors";
import path from "path";
import { existsSync, readFileSync, statSync, watch } from "fs";
import { execSync } from "child_process";
import os from "os";
import {
  tachikomaStatus,
  tachikomaDispatch,
  readWorkRequests,
  PROJECTS_DIR,
} from "./state.ts";
import { streamChat } from "./claude.ts";
import type { ChatMessage } from "./claude.ts";

const HOME = os.homedir();
const BMO_FACES_DIR = path.join(HOME, "Desktop", "bmo faces", "set");

if (!process.env.ANTHROPIC_API_KEY) {
  console.error("[server] ERROR: ANTHROPIC_API_KEY is not set. Exiting.");
  process.exit(1);
}

const app = express();
app.use(cors());
app.use(express.json());

// ── Static (prod build) ───────────────────────────────────────────────────────
const distPath = path.join(path.dirname(new URL(import.meta.url).pathname), "..", "dist");
if (existsSync(distPath)) {
  app.use(express.static(distPath));
}

// ── GET /api/status ───────────────────────────────────────────────────────────
app.get("/api/status", (_req, res) => {
  try {
    const states = tachikomaStatus();
    res.json(states);
  } catch (err) {
    console.error("[server] /api/status error:", err);
    res.status(500).json({ error: "Failed to read tachikoma status" });
  }
});

// ── GET /api/queue ────────────────────────────────────────────────────────────
app.get("/api/queue", (_req, res) => {
  try {
    const requests = readWorkRequests();
    const states = tachikomaStatus();

    const items = requests.map((r) => {
      const matching = states.find(
        (s) => s.branch === `tachikoma/${r.slug}`
      );
      return {
        slug: r.slug,
        status: (["open", "grabbed", "done"].includes(r.status)
          ? r.status
          : "open") as "open" | "grabbed" | "done",
        targetRepo: r.targetRepo,
        priority: r.priority,
        goal: r.goal,
        qualityBar: r.qualityBar,
        activeBranch: matching?.branch ?? null,
      };
    });

    res.json(items);
  } catch (err) {
    console.error("[server] /api/queue error:", err);
    res.status(500).json({ error: "Failed to read work queue" });
  }
});

// ── GET /api/logs/:slug (SSE) ─────────────────────────────────────────────────
app.get("/api/logs/:slug", (req, res) => {
  const { slug } = req.params;

  const states = tachikomaStatus();
  const state = states.find((s) => s.slug === slug);

  if (!state) {
    res.status(404).json({ error: `No tachikoma found for slug: ${slug}` });
    return;
  }

  const logFile = path.join(state.worktree, ".tachikoma", "run.log");
  const outcomeFile = path.join(state.worktree, ".tachikoma", "outcome");

  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders();

  const sendLine = (line: string) => {
    res.write(`data: ${JSON.stringify(line)}\n\n`);
  };

  // Send last 200 lines on connect
  if (existsSync(logFile)) {
    const content = readFileSync(logFile, "utf8");
    const lines = content.split("\n");
    const last200 = lines.slice(Math.max(0, lines.length - 200));
    for (const line of last200) {
      if (line) sendLine(line);
    }
  }

  // Check if already done
  if (existsSync(outcomeFile)) {
    res.write("event: done\ndata: end\n\n");
    res.end();
    return;
  }

  // Poll for new log lines and outcome
  let lastSize = existsSync(logFile) ? statSync(logFile).size : 0;
  let closed = false;

  const poll = setInterval(() => {
    if (closed) {
      clearInterval(poll);
      return;
    }

    // Stream new log content
    if (existsSync(logFile)) {
      const current = statSync(logFile).size;
      if (current > lastSize) {
        const fd = readFileSync(logFile, "utf8");
        const newContent = fd.slice(lastSize);
        lastSize = current;
        const newLines = newContent.split("\n");
        for (const line of newLines) {
          if (line) sendLine(line);
        }
      }
    }

    // Check for outcome
    if (existsSync(outcomeFile)) {
      clearInterval(poll);
      res.write("event: done\ndata: end\n\n");
      res.end();
    }
  }, 500);

  req.on("close", () => {
    closed = true;
    clearInterval(poll);
  });
});

// ── GET /api/bmo/:face.png ────────────────────────────────────────────────────
app.get("/api/bmo/:face", (req, res) => {
  const { face } = req.params;
  // face param includes ".png" suffix
  const faceName = face.replace(".png", "");
  const validFaces = [
    "smile",
    "content",
    "neutral",
    "angry",
    "disbelief",
    "frustrated",
    "out-of-wack",
  ];

  // smile.png doesn't exist — fall back to content.png
  const resolvedFace = faceName === "smile" ? "content" : faceName;
  const resolvedName = validFaces.includes(resolvedFace) ? resolvedFace : "neutral";
  const filePath = path.join(BMO_FACES_DIR, `${resolvedName}.png`);

  if (!existsSync(filePath)) {
    res.status(404).json({ error: `BMO face not found: ${resolvedName}` });
    return;
  }

  res.setHeader("Content-Type", "image/png");
  res.setHeader("Cache-Control", "public, max-age=86400");
  res.sendFile(filePath);
});

// ── POST /api/stop ────────────────────────────────────────────────────────────
app.post("/api/stop", (req, res) => {
  const body = req.body as { slug?: unknown };
  if (typeof body.slug !== "string") {
    res.status(400).json({ ok: false, error: "slug required" });
    return;
  }

  const states = tachikomaStatus();
  const state = states.find((s) => s.slug === body.slug);

  if (!state || state.pid === null) {
    res.status(404).json({ ok: false, error: "No running tachikoma found" });
    return;
  }

  try {
    process.kill(state.pid, "SIGTERM");
    res.json({ ok: true });
  } catch (err) {
    console.error("[server] /api/stop error:", err);
    res.status(500).json({
      ok: false,
      error: err instanceof Error ? err.message : "Failed to stop",
    });
  }
});

// ── POST /api/abandon ─────────────────────────────────────────────────────────
app.post("/api/abandon", (req, res) => {
  const body = req.body as { slug?: unknown };
  if (typeof body.slug !== "string") {
    res.status(400).json({ ok: false, error: "slug required" });
    return;
  }

  const states = tachikomaStatus();
  const state = states.find((s) => s.slug === body.slug);

  if (!state) {
    res.status(404).json({ ok: false, error: "No tachikoma found" });
    return;
  }

  try {
    const repoPath = path.join(PROJECTS_DIR, state.repo);
    execSync(`git worktree remove --force "${state.worktree}"`, {
      stdio: "pipe",
    });
    execSync(`git -C "${repoPath}" branch -D "${state.branch}"`, {
      stdio: "pipe",
    });
    res.json({ ok: true });
  } catch (err) {
    console.error("[server] /api/abandon error:", err);
    res.status(500).json({
      ok: false,
      error: err instanceof Error ? err.message : "Failed to abandon",
    });
  }
});

// ── POST /api/cleanup ─────────────────────────────────────────────────────────
app.post("/api/cleanup", (req, res) => {
  const body = req.body as { slug?: unknown };
  if (typeof body.slug !== "string") {
    res.status(400).json({ ok: false, error: "slug required" });
    return;
  }

  const states = tachikomaStatus();
  const state = states.find((s) => s.slug === body.slug);

  if (!state) {
    res.status(404).json({ ok: false, error: "No tachikoma found" });
    return;
  }

  try {
    const repoPath = path.join(PROJECTS_DIR, state.repo);
    execSync(`git worktree remove --force "${state.worktree}"`, {
      stdio: "pipe",
    });
    execSync(`git -C "${repoPath}" branch -D "${state.branch}"`, {
      stdio: "pipe",
    });
    res.json({ ok: true });
  } catch (err) {
    console.error("[server] /api/cleanup error:", err);
    res.status(500).json({
      ok: false,
      error: err instanceof Error ? err.message : "Failed to cleanup",
    });
  }
});

// ── POST /api/dispatch ────────────────────────────────────────────────────────
app.post("/api/dispatch", async (req, res) => {
  const body = req.body as { cap?: unknown };
  const rawCap = body.cap;
  const cap =
    typeof rawCap === "number" ? Math.min(Math.max(1, rawCap), 50) : 5;

  try {
    const result = await tachikomaDispatch(cap);
    res.json({ ok: true, result });
  } catch (err) {
    console.error("[server] /api/dispatch error:", err);
    res.status(500).json({
      ok: false,
      error: err instanceof Error ? err.message : "Dispatch failed",
    });
  }
});

// ── POST /api/chat (SSE) ──────────────────────────────────────────────────────
app.post("/api/chat", async (req, res) => {
  const body = req.body as { messages?: unknown };
  if (!Array.isArray(body.messages)) {
    res.status(400).json({ error: "messages array required" });
    return;
  }

  const messages = body.messages as ChatMessage[];
  await streamChat(messages, res);
});

// ── SPA fallback ──────────────────────────────────────────────────────────────
if (existsSync(distPath)) {
  app.get("*", (_req, res) => {
    res.sendFile(path.join(distPath, "index.html"));
  });
}

// ── Start ─────────────────────────────────────────────────────────────────────
app.listen(4000, () => {
  console.log("[server] Tachikoma UI running on http://localhost:4000");
});
