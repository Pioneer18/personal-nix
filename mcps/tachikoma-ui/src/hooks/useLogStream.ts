import { useState, useEffect, useRef } from "react";

interface UseLogStreamResult {
  lines: string[];
  connected: boolean;
}

export function useLogStream(slug: string | null): UseLogStreamResult {
  const [lines, setLines] = useState<string[]>([]);
  const [connected, setConnected] = useState(false);
  const controllerRef = useRef<AbortController | null>(null);

  useEffect(() => {
    if (!slug) {
      setLines([]);
      setConnected(false);
      return;
    }

    setLines([]);
    setConnected(false);

    const controller = new AbortController();
    controllerRef.current = controller;

    (async () => {
      try {
        const res = await fetch(`/api/logs/${encodeURIComponent(slug)}`, {
          signal: controller.signal,
        });

        if (!res.body) return;
        setConnected(true);

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
            const lines2 = part.split("\n");
            const eventLine = lines2.find((l) => l.startsWith("event:"));
            const dataLine = lines2.find((l) => l.startsWith("data:"));
            const eventType = eventLine?.slice(6).trim();
            const dataStr = dataLine?.slice(5).trim();

            if (!dataStr) continue;

            if (eventType === "done") {
              setConnected(false);
              return;
            }

            // Regular log line
            try {
              const line = JSON.parse(dataStr) as string;
              setLines((prev) => [...prev, line]);
            } catch {
              // ignore parse errors
            }
          }
        }
      } catch (err) {
        if ((err as { name?: string }).name !== "AbortError") {
          setConnected(false);
        }
      }
    })();

    return () => {
      controller.abort();
      setConnected(false);
    };
  }, [slug]);

  return { lines, connected };
}
