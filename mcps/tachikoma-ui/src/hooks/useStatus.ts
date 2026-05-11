import { useState, useEffect, useCallback } from "react";
import type { TachikomaState, WorkQueueItem } from "@/types";
import { fetchStatus, fetchQueue } from "@/lib/api";

interface UseStatusResult {
  tachikomas: TachikomaState[];
  queue: WorkQueueItem[];
  loading: boolean;
  error: string | null;
  refresh: () => void;
}

export function useStatus(): UseStatusResult {
  const [tachikomas, setTachikomas] = useState<TachikomaState[]>([]);
  const [queue, setQueue] = useState<WorkQueueItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [states, items] = await Promise.all([
        fetchStatus(),
        fetchQueue(),
      ]);
      setTachikomas(states);
      setQueue(items);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load status");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
    const interval = setInterval(() => void load(), 5000);
    return () => clearInterval(interval);
  }, [load]);

  return { tachikomas, queue, loading, error, refresh: load };
}
