import { useEffect, useRef } from "react";
import * as ScrollArea from "@radix-ui/react-scroll-area";
import type { TachikomaState } from "@/types";
import { useLogStream } from "@/hooks/useLogStream";

interface LogDrawerProps {
  slug: string | null;
  onClose: () => void;
  tachikomas: TachikomaState[];
}

const STATUS_BADGE: Record<
  TachikomaState["status"],
  { label: string; className: string }
> = {
  running: {
    label: "running",
    className: "bg-green-900/60 text-green-400 border border-green-700/60",
  },
  complete: {
    label: "complete",
    className: "bg-zinc-800 text-zinc-400 border border-zinc-700",
  },
  cap: {
    label: "cap",
    className: "bg-amber-900/60 text-amber-400 border border-amber-700/60",
  },
  error: {
    label: "error",
    className: "bg-red-900/60 text-red-400 border border-red-700/60",
  },
  stopped: {
    label: "stopped",
    className: "bg-zinc-800 text-zinc-500 border border-zinc-700",
  },
  unknown: {
    label: "unknown",
    className: "bg-zinc-800 text-zinc-500 border border-zinc-700",
  },
  stale: {
    label: "stale",
    className: "bg-amber-900/60 text-amber-400 border border-amber-700/60",
  },
};

export function LogDrawer({ slug, onClose, tachikomas }: LogDrawerProps) {
  const { lines, connected } = useLogStream(slug);
  const viewportRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!slug) return;
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [slug, onClose]);

  useEffect(() => {
    const el = viewportRef.current;
    if (el) {
      el.scrollTop = el.scrollHeight;
    }
  }, [lines.length]);

  if (!slug) return null;

  const state = tachikomas.find((t) => t.slug === slug);

  return (
    <aside className="fixed top-0 right-0 h-full w-[40vw] bg-zinc-900 border-l border-zinc-800 z-50 flex flex-col">
      <header className="flex-shrink-0 h-16 flex items-center gap-3 px-4 border-b border-zinc-800">
        {state ? (
          <>
            <img
              src={`/api/bmo/${state.bmoFace}.png`}
              alt={`BMO ${state.bmoFace}`}
              className="h-10 w-10 object-contain"
            />
            <div className="flex-1 min-w-0 flex items-center gap-2">
              <span className="text-zinc-100 font-mono text-sm font-medium truncate">
                {state.slug}
              </span>
              <span
                className={`inline-flex items-center px-1.5 py-0.5 rounded text-xs font-mono ${STATUS_BADGE[state.status].className}`}
              >
                {STATUS_BADGE[state.status].label}
              </span>
            </div>
          </>
        ) : (
          <div className="flex-1 text-zinc-400 text-sm">Run not found</div>
        )}
        <button
          onClick={onClose}
          aria-label="Close log drawer"
          className="flex-shrink-0 w-8 h-8 flex items-center justify-center rounded text-zinc-500 hover:bg-zinc-800 hover:text-zinc-200 transition-colors"
        >
          ×
        </button>
      </header>

      <div className="flex-1 overflow-hidden">
        {state ? (
          <ScrollArea.Root className="h-full w-full overflow-hidden">
            <ScrollArea.Viewport
              ref={viewportRef}
              className="h-full w-full"
            >
              <pre className="font-mono text-xs text-zinc-300 whitespace-pre-wrap p-4">
                {lines.join("\n")}
              </pre>
            </ScrollArea.Viewport>
            <ScrollArea.Scrollbar
              orientation="vertical"
              className="flex w-2 touch-none select-none bg-transparent"
            >
              <ScrollArea.Thumb className="relative flex-1 rounded-full bg-zinc-700 hover:bg-zinc-600" />
            </ScrollArea.Scrollbar>
          </ScrollArea.Root>
        ) : (
          <div className="p-4 text-zinc-500 text-sm">
            No state available for this run.
          </div>
        )}
      </div>

      <footer className="flex-shrink-0 h-8 flex items-center px-4 border-t border-zinc-800 text-xs font-mono">
        {connected ? (
          <span className="text-green-400">● Streaming</span>
        ) : (
          <span className="text-amber-400">◌ Reconnecting...</span>
        )}
      </footer>
    </aside>
  );
}
