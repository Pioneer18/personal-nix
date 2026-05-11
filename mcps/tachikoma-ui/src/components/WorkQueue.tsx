import type { WorkQueueItem } from "@/types";

interface WorkQueueProps {
  items: WorkQueueItem[];
}

const STATUS_BADGE: Record<
  WorkQueueItem["status"],
  { label: string; className: string }
> = {
  open: {
    label: "open",
    className: "bg-zinc-800 text-zinc-400 border border-zinc-700",
  },
  grabbed: {
    label: "grabbed",
    className: "bg-blue-900/60 text-blue-400 border border-blue-700/60",
  },
  done: {
    label: "done",
    className: "bg-green-900/60 text-green-400 border border-green-700/60",
  },
};

export function WorkQueue({ items }: WorkQueueProps) {
  return (
    <section className="flex flex-col gap-3 min-h-0">
      <h2 className="text-xs font-semibold text-zinc-500 uppercase tracking-widest px-1">
        Work Queue
      </h2>

      {items.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-8 gap-1 text-center">
          <p className="text-zinc-400 text-sm font-medium">All quiet.</p>
          <p className="text-zinc-600 text-xs">
            Nothing queued — what are we building?
          </p>
        </div>
      ) : (
        <div className="flex flex-col gap-1">
          {items.map((item) => {
            const badge = STATUS_BADGE[item.status];
            const isActive = item.activeBranch !== null;
            return (
              <div
                key={item.slug}
                className={`flex items-start gap-3 px-3 py-2.5 rounded-md bg-zinc-900 border transition-colors ${
                  isActive
                    ? "border-l-2 border-l-blue-500 border-r-zinc-800 border-t-zinc-800 border-b-zinc-800"
                    : "border-zinc-800"
                }`}
              >
                {/* Priority badge */}
                <span className="flex-shrink-0 mt-0.5 text-xs font-mono text-zinc-600 w-6 text-right">
                  {item.priority}
                </span>

                {/* Slug + goal */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-zinc-200 font-mono text-xs font-medium">
                      {item.slug}
                    </span>
                    <span
                      className={`inline-flex items-center px-1.5 py-0.5 rounded text-xs font-mono ${badge.className}`}
                    >
                      {badge.label}
                    </span>
                  </div>
                  {item.goal && (
                    <p className="text-zinc-500 text-xs mt-0.5 truncate">
                      {item.goal}
                    </p>
                  )}
                </div>

                {/* Repo */}
                <span className="flex-shrink-0 text-xs text-zinc-600 font-mono truncate max-w-[120px]">
                  {item.targetRepo.split("/").pop()}
                </span>
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
