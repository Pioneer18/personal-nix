import Anthropic from "@anthropic-ai/sdk";
import type { Response } from "express";

const SYSTEM_PROMPT = `You are the Tachikoma launch assistant — Ghost in the Shell vibes, concise and direct. You help the user manage their autonomous coding queue.

## What you can do

**Launch a run**
Ask for the iteration cap (default 5, max 50), then output:
{"action": "dispatch", "cap": N}

**Stop / abandon a run**
{"action": "stop", "slug": "..."}
{"action": "abandon", "slug": "..."}

**Create a new work request**
Gather: goal (required), target_repo (default ~/projects/personal-nix), stop_condition (required), quality_bar (prototype|production|library, default production).
Derive slug: lowercase, dashes, max 40 chars, from the goal.
Then output:
{"action": "create_work_request", "slug": "...", "target_repo": "...", "goal": "...", "stop_condition": "...", "quality_bar": "..."}

**Delete a done work request**
{"action": "delete_work_request", "slug": "..."}
Only for items with status=done.

## Rules
- Keep responses short — one or two sentences max
- Ask only the missing required fields, not everything at once
- Don't pretend to use tools you don't have — your only output channel is the JSON actions above`;



export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

interface DispatchAction {
  action: "dispatch";
  cap: number;
}

interface SlugAction {
  action: "stop" | "abandon" | "delete_work_request";
  slug: string;
}

interface CreateWorkRequestAction {
  action: "create_work_request";
  slug: string;
  target_repo: string;
  goal: string;
  stop_condition: string;
  quality_bar: string;
}

type ActionEvent = DispatchAction | SlugAction | CreateWorkRequestAction;

function extractAction(text: string): ActionEvent | null {
  const match = text.match(/\{[^{}]*"action"\s*:\s*"[^"]+[^{}]*\}/);
  if (!match) return null;
  try {
    const parsed: unknown = JSON.parse(match[0]);
    if (
      typeof parsed !== "object" ||
      parsed === null ||
      !("action" in parsed)
    )
      return null;
    const obj = parsed as Record<string, unknown>;
    if (obj.action === "dispatch" && typeof obj.cap === "number") {
      return { action: "dispatch", cap: obj.cap };
    }
    if (
      (obj.action === "stop" ||
        obj.action === "abandon" ||
        obj.action === "delete_work_request") &&
      typeof obj.slug === "string"
    ) {
      return { action: obj.action, slug: obj.slug };
    }
    if (
      obj.action === "create_work_request" &&
      typeof obj.slug === "string" &&
      typeof obj.goal === "string" &&
      typeof obj.stop_condition === "string"
    ) {
      return {
        action: "create_work_request",
        slug: obj.slug,
        target_repo: typeof obj.target_repo === "string" ? obj.target_repo : "~/projects/personal-nix",
        goal: obj.goal,
        stop_condition: obj.stop_condition,
        quality_bar: typeof obj.quality_bar === "string" ? obj.quality_bar : "production",
      };
    }
    return null;
  } catch {
    return null;
  }
}

export async function streamChat(
  messages: ChatMessage[],
  res: Response
): Promise<void> {
  const apiKey = process.env.ANTHROPIC_API_KEY_COMPANY;
  if (!apiKey) {
    res.status(500).json({ error: "ANTHROPIC_API_KEY_COMPANY not set" });
    return;
  }

  const client = new Anthropic({ apiKey });

  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders();

  let fullText = "";

  try {
    const stream = await client.messages.stream({
      model: "claude-sonnet-4-6",
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      messages: messages.map((m) => ({ role: m.role, content: m.content })),
    });

    for await (const event of stream) {
      if (
        event.type === "content_block_delta" &&
        event.delta.type === "text_delta"
      ) {
        const token = event.delta.text;
        fullText += token;
        res.write(`data: ${JSON.stringify(token)}\n\n`);
      }
    }

    // Check for action after full text is accumulated
    const action = extractAction(fullText);
    if (action) {
      if (action.action === "dispatch") {
        res.write(
          `event: action\ndata: ${JSON.stringify({ type: "dispatch", cap: action.cap })}\n\n`
        );
      } else if (action.action === "create_work_request") {
        res.write(
          `event: action\ndata: ${JSON.stringify({ type: "create_work_request", ...action })}\n\n`
        );
      } else {
        res.write(
          `event: action\ndata: ${JSON.stringify({ type: action.action, slug: action.slug })}\n\n`
        );
      }
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    res.write(`event: error\ndata: ${JSON.stringify({ message: msg })}\n\n`);
  } finally {
    res.write("event: done\ndata: end\n\n");
    res.end();
  }
}
