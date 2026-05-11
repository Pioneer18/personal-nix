import type { TachikomaState } from "@/types";
import { TachikomaCard } from "./TachikomaCard";

interface ActiveCardsProps {
  tachikomas: TachikomaState[];
  onOpenLog: (slug: string) => void;
  onRefresh: () => void;
}

export function ActiveCards({
  tachikomas,
  onOpenLog,
  onRefresh,
}: ActiveCardsProps) {
  return (
    <section className="flex flex-col gap-3 min-h-0">
      <h2 className="text-xs font-semibold text-zinc-500 uppercase tracking-widest px-1">
        Active
      </h2>

      {tachikomas.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-12 gap-2 text-center">
          <span className="text-zinc-600 text-2xl">◎</span>
          <p className="text-zinc-500 text-sm">No active runs.</p>
          <p className="text-zinc-600 text-xs">
            Dispatch a work request to launch a Ghost.
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {tachikomas.map((t) => (
            <TachikomaCard
              key={t.worktree}
              state={t}
              onOpenLog={onOpenLog}
              onRefresh={onRefresh}
            />
          ))}
        </div>
      )}
    </section>
  );
}
