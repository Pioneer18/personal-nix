import { useState } from "react";
import type { TachikomaState } from "@/types";
import { StopModal } from "./StopModal";
import { AbandonModal } from "./AbandonModal";
import { CleanupModal } from "./CleanupModal";
import { stopTachikoma, abandonTachikoma, cleanupTachikoma } from "@/lib/api";

interface TachikomaCardProps {
  state: TachikomaState;
  onOpenLog: (slug: string) => void;
  onRefresh: () => void;
}

const STATUS_BADGE: Record<
  TachikomaState["status"],
  { label: string; icon: string; className: string }
> = {
  running: {
    label: "running",
    icon: "●",
    className: "bg-green-900/60 text-green-400 border border-green-700/60",
  },
  complete: {
    label: "complete",
    icon: "✓",
    className: "bg-zinc-800 text-zinc-400 border border-zinc-700",
  },
  cap: {
    label: "cap",
    icon: "▲",
    className: "bg-amber-900/60 text-amber-400 border border-amber-700/60",
  },
  error: {
    label: "error",
    icon: "✕",
    className: "bg-red-900/60 text-red-400 border border-red-700/60",
  },
  stopped: {
    label: "stopped",
    icon: "◼",
    className: "bg-zinc-800 text-zinc-500 border border-zinc-700",
  },
  unknown: {
    label: "unknown",
    icon: "?",
    className: "bg-zinc-800 text-zinc-500 border border-zinc-700",
  },
  stale: {
    label: "stale",
    icon: "⚠",
    className: "bg-amber-900/60 text-amber-400 border border-amber-700/60",
  },
};

export function TachikomaCard({
  state,
  onOpenLog,
  onRefresh,
}: TachikomaCardProps) {
  const [stopOpen, setStopOpen] = useState(false);
  const [abandonOpen, setAbandonOpen] = useState(false);
  const [cleanupOpen, setCleanupOpen] = useState(false);
  const [busy, setBusy] = useState(false);

  const badge = STATUS_BADGE[state.status];

  const handleStop = async () => {
    setBusy(true);
    try {
      await stopTachikoma(state.slug);
      onRefresh();
    } catch (err) {
      console.error("[TachikomaCard] stop error:", err);
    } finally {
      setBusy(false);
      setStopOpen(false);
    }
  };

  const handleAbandon = async () => {
    setBusy(true);
    try {
      await abandonTachikoma(state.slug);
      onRefresh();
    } catch (err) {
      console.error("[TachikomaCard] abandon error:", err);
    } finally {
      setBusy(false);
      setAbandonOpen(false);
    }
  };

  const handleCleanup = async () => {
    setBusy(true);
    try {
      await cleanupTachikoma(state.slug);
      onRefresh();
    } catch (err) {
      console.error("[TachikomaCard] cleanup error:", err);
    } finally {
      setBusy(false);
      setCleanupOpen(false);
    }
  };

  return (
    <>
      <div
        className="bg-zinc-900 border border-zinc-800 rounded-lg p-4 flex flex-col gap-3 cursor-pointer hover:border-zinc-600 transition-colors"
        onClick={() => onOpenLog(state.slug)}
        role="button"
        tabIndex={0}
        onKeyDown={(e) => e.key === "Enter" && onOpenLog(state.slug)}
        aria-label={`Open logs for ${state.slug}`}
      >
        {/* Header row */}
        <div className="flex items-start gap-3">
          <img
            src={`/api/bmo/${state.bmoFace}.png`}
            alt={`BMO ${state.bmoFace}`}
            className="w-16 h-16 rounded-md object-cover flex-shrink-0"
          />
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-zinc-100 font-mono text-sm font-medium truncate">
                {state.slug}
              </span>
              <span
                className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-xs font-mono ${badge.className} ${state.status === "running" ? "animate-pulse" : ""}`}
              >
                <span>{badge.icon}</span>
                {badge.label}
              </span>
            </div>
            <div className="text-zinc-500 text-xs mt-0.5 truncate">
              {state.repo}
            </div>
            {state.iter && (
              <div className="text-zinc-400 text-xs mt-0.5 font-mono">
                iter {state.iter}
              </div>
            )}
          </div>
        </div>

        {/* Progress note */}
        {state.lastProgress && (
          <p className="text-zinc-400 text-xs line-clamp-2 leading-relaxed">
            {state.lastProgress}
          </p>
        )}

        {/* Action buttons */}
        <div
          className="flex gap-2 flex-wrap"
          onClick={(e) => e.stopPropagation()}
        >
          {state.status === "running" && (
            <button
              disabled={busy}
              onClick={() => setStopOpen(true)}
              className="px-2.5 py-1 text-xs rounded bg-amber-900/50 text-amber-300 border border-amber-700/50 hover:bg-amber-900/80 transition-colors disabled:opacity-50"
            >
              Stop
            </button>
          )}
          {(state.status === "error" || state.status === "cap") && (
            <button
              disabled={busy}
              onClick={() => setAbandonOpen(true)}
              className="px-2.5 py-1 text-xs rounded bg-zinc-800 text-zinc-300 border border-zinc-700 hover:bg-zinc-700 transition-colors disabled:opacity-50"
            >
              Retry / Ship
            </button>
          )}
          {state.status === "stale" && (
            <button
              disabled={busy}
              onClick={() => setCleanupOpen(true)}
              className="px-2.5 py-1 text-xs rounded bg-zinc-800 text-zinc-300 border border-zinc-700 hover:bg-zinc-700 transition-colors disabled:opacity-50"
            >
              Cleanup
            </button>
          )}
          <button
            disabled={busy}
            onClick={() => setAbandonOpen(true)}
            className="px-2.5 py-1 text-xs rounded bg-zinc-800 text-zinc-500 border border-zinc-700 hover:bg-red-900/40 hover:text-red-400 hover:border-red-700/50 transition-colors disabled:opacity-50"
          >
            Abandon
          </button>
        </div>
      </div>

      <StopModal
        open={stopOpen}
        slug={state.slug}
        onConfirm={() => void handleStop()}
        onCancel={() => setStopOpen(false)}
      />
      <AbandonModal
        open={abandonOpen}
        slug={state.slug}
        onConfirm={() => void handleAbandon()}
        onCancel={() => setAbandonOpen(false)}
      />
      <CleanupModal
        open={cleanupOpen}
        slug={state.slug}
        onConfirm={() => void handleCleanup()}
        onCancel={() => setCleanupOpen(false)}
      />
    </>
  );
}
