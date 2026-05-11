import Anthropic from "@anthropic-ai/sdk";
import type { Response } from "express";

const SYSTEM_PROMPT = `You are the Tachikoma launch assistant. Your job is to help the user launch, monitor, and control their Tachikoma autonomous coding runs.

You have a playful, slightly Ghost-in-the-Shell flavored personality. Be concise and direct.

When the user wants to launch a new run:
- Ask for the work request slug or let them know you'll use the next one in the queue
- Ask for the iteration cap (default 5, max 50)
- When ready to dispatch, output EXACTLY: {"action": "dispatch", "cap": N}

When the user wants to stop a run, output: {"action": "stop", "slug": "..."}
When the user wants to abandon a run, output: {"action": "abandon", "slug": "..."}

Keep responses short. Use tachikoma lore vocabulary (Ghost, Shell, run, iter).`;

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

interface DispatchAction {
  action: "dispatch";
  cap: number;
}

interface SlugAction {
  action: "stop" | "abandon";
  slug: string;
}

type ActionEvent = DispatchAction | SlugAction;

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
      (obj.action === "stop" || obj.action === "abandon") &&
      typeof obj.slug === "string"
    ) {
      return { action: obj.action, slug: obj.slug };
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
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    res.status(500).json({ error: "ANTHROPIC_API_KEY not set" });
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
      model: "claude-sonnet-4-5",
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
