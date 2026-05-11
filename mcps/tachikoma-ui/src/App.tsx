import { useState, useEffect } from "react";
import { useStatus } from "@/hooks/useStatus";
import { WorkQueue } from "@/components/WorkQueue";
import { ActiveCards } from "@/components/ActiveCards";
import { LogDrawer } from "@/components/LogDrawer";
import { ChatBar } from "@/components/ChatBar";

function useSecondsAgo(date: Date | null): string | null {
  const [, setTick] = useState(0);
  useEffect(() => {
    const t = setInterval(() => setTick((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, []);
  if (!date) return null;
  const s = Math.floor((Date.now() - date.getTime()) / 1000);
  if (s < 5) return "just now";
  if (s < 60) return `${s}s ago`;
  return `${Math.floor(s / 60)}m ago`;
}

export function App() {
  const [selectedSlug, setSelectedSlug] = useState<string | null>(null);
  const { tachikomas, queue, loading, isRefreshing, lastRefreshed, error, refresh } = useStatus();
  const refreshedAgo = useSecondsAgo(lastRefreshed);

  return (
    <div className="h-screen flex flex-col bg-zinc-950 text-zinc-100 font-mono">
      <header className="flex-shrink-0 flex items-center justify-between px-6 py-3 border-b border-zinc-800">
        <h1 className="text-sm font-semibold tracking-widest uppercase text-zinc-100">
          Tachikoma
        </h1>
        <div className="flex items-center gap-3 text-xs text-zinc-500">
          {error ? (
            <span className="text-red-400">⚠ {error}</span>
          ) : loading ? (
            <span>◌ Loading...</span>
          ) : (
            <span>
              <span className="text-green-400">●</span> polling · {refreshedAgo ?? "5s"}
            </span>
          )}
          <button
            onClick={() => void refresh()}
            disabled={isRefreshing}
            title="Hard refresh"
            className="flex items-center gap-1 px-2 py-1 rounded border border-zinc-700 hover:border-zinc-500 hover:text-zinc-300 disabled:opacity-40 transition-colors"
          >
            <span className={isRefreshing ? "animate-spin inline-block" : ""}>↻</span>
            {isRefreshing ? "refreshing…" : "refresh"}
          </button>
        </div>
      </header>

      <main className="flex-1 overflow-y-auto px-6 py-6 pb-[240px]">
        <div className="flex flex-col gap-8 max-w-5xl mx-auto">
          <WorkQueue items={queue} />
          <ActiveCards
            tachikomas={tachikomas}
            onOpenLog={setSelectedSlug}
            onRefresh={refresh}
          />
        </div>
      </main>

      <LogDrawer
        slug={selectedSlug}
        onClose={() => setSelectedSlug(null)}
        tachikomas={tachikomas}
      />

      <ChatBar />
    </div>
  );
}
