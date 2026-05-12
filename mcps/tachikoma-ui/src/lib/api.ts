import type { TachikomaState, WorkQueueItem, ChatMessage, ActionEvent } from "@/types";

// ── Fetch helpers ─────────────────────────────────────────────────────────────

export async function fetchStatus(): Promise<TachikomaState[]> {
  const res = await fetch("/api/status");
  if (!res.ok) throw new Error(`/api/status failed: ${res.status}`);
  return res.json() as Promise<TachikomaState[]>;
}

export async function fetchQueue(): Promise<WorkQueueItem[]> {
  const res = await fetch("/api/queue");
  if (!res.ok) throw new Error(`/api/queue failed: ${res.status}`);
  return res.json() as Promise<WorkQueueItem[]>;
}

export async function stopTachikoma(slug: string): Promise<void> {
  const res = await fetch("/api/stop", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ slug }),
  });
  if (!res.ok) throw new Error(`/api/stop failed: ${res.status}`);
}

export async function abandonTachikoma(slug: string): Promise<void> {
  const res = await fetch("/api/abandon", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ slug }),
  });
  if (!res.ok) throw new Error(`/api/abandon failed: ${res.status}`);
}

export async function cleanupTachikoma(slug: string): Promise<void> {
  const res = await fetch("/api/cleanup", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ slug }),
  });
  if (!res.ok) throw new Error(`/api/cleanup failed: ${res.status}`);
}

export async function createWorkRequest(opts: {
  slug: string;
  target_repo: string;
  goal: string;
  stop_condition: string;
  quality_bar: string;
}): Promise<void> {
  const res = await fetch("/api/work-request", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(opts),
  });
  const data = await res.json() as { ok: boolean; error?: string };
  if (!data.ok) throw new Error(data.error ?? "Failed to create work request");
}

export async function deleteWorkRequest(slug: string): Promise<void> {
  const res = await fetch(`/api/work-request/${encodeURIComponent(slug)}`, {
    method: "DELETE",
  });
  const data = await res.json() as { ok: boolean; error?: string };
  if (!data.ok) throw new Error(data.error ?? "Failed to delete work request");
}

export async function dispatch(cap: number): Promise<object> {
  const res = await fetch("/api/dispatch", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ cap }),
  });
  const data = await res.json() as { ok: boolean; result: object; error?: string };
  if (!data.ok) throw new Error(data.error ?? "Dispatch failed");
  return data.result;
}

// ── Chat SSE ──────────────────────────────────────────────────────────────────

export function openChatStream(
  messages: ChatMessage[],
  onToken: (token: string) => void,
  onAction: (action: ActionEvent) => void,
  onDone: () => void,
  onError: (msg: string) => void
): () => void {
  const controller = new AbortController();

  (async () => {
    try {
      const res = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ messages }),
        signal: controller.signal,
      });

      if (!res.body) throw new Error("No response body");

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });

        const parts = buffer.split("\n\n");
        buffer = parts.pop() ?? "";

        for (const part of parts) {
          const lines = part.split("\n");
          const eventLine = lines.find((l) => l.startsWith("event:"));
          const dataLine = lines.find((l) => l.startsWith("data:"));
          const eventType = eventLine?.slice(6).trim();
          const dataStr = dataLine?.slice(5).trim();

          if (!dataStr) continue;

          if (eventType === "action") {
            try {
              const action = JSON.parse(dataStr) as ActionEvent;
              onAction(action);
            } catch {
              // ignore parse errors
            }
          } else if (eventType === "done") {
            onDone();
          } else if (eventType === "error") {
            try {
              const err = JSON.parse(dataStr) as { message: string };
              onError(err.message);
            } catch {
              onError(dataStr);
            }
          } else {
            // regular token
            try {
              const token = JSON.parse(dataStr) as string;
              onToken(token);
            } catch {
              // ignore
            }
          }
        }
      }
    } catch (err) {
      if ((err as { name?: string }).name !== "AbortError") {
        onError(err instanceof Error ? err.message : String(err));
      }
    }
  })();

  return () => controller.abort();
}
