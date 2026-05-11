import { useState } from "react";
import { useStatus } from "@/hooks/useStatus";
import { WorkQueue } from "@/components/WorkQueue";
import { ActiveCards } from "@/components/ActiveCards";
import { LogDrawer } from "@/components/LogDrawer";
import { ChatBar } from "@/components/ChatBar";

export function App() {
  const [selectedSlug, setSelectedSlug] = useState<string | null>(null);
  const { tachikomas, queue, loading, error, refresh } = useStatus();

  return (
    <div className="h-screen flex flex-col bg-zinc-950 text-zinc-100 font-mono">
      <header className="flex-shrink-0 flex items-center justify-between px-6 py-3 border-b border-zinc-800">
        <h1 className="text-sm font-semibold tracking-widest uppercase text-zinc-100">
          Tachikoma
        </h1>
        <div className="flex items-center gap-2 text-xs text-zinc-500">
          {error ? (
            <span className="text-red-400">⚠ {error}</span>
          ) : loading ? (
            <span>◌ Loading...</span>
          ) : (
            <span>
              <span className="text-green-400">●</span> polling · 5s
            </span>
          )}
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
