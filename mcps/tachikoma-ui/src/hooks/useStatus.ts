import { useState, useEffect, useCallback } from "react";
import type { TachikomaState, WorkQueueItem } from "@/types";
import { fetchStatus, fetchQueue } from "@/lib/api";

interface UseStatusResult {
  tachikomas: TachikomaState[];
  queue: WorkQueueItem[];
  loading: boolean;
  isRefreshing: boolean;
  lastRefreshed: Date | null;
  error: string | null;
  refresh: () => Promise<void>;
}

export function useStatus(): UseStatusResult {
  const [tachikomas, setTachikomas] = useState<TachikomaState[]>([]);
  const [queue, setQueue] = useState<WorkQueueItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [lastRefreshed, setLastRefreshed] = useState<Date | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (manual = false) => {
    if (manual) setIsRefreshing(true);
    try {
      const [states, items] = await Promise.all([
        fetchStatus(),
        fetchQueue(),
      ]);
      setTachikomas(states);
      setQueue(items);
      setLastRefreshed(new Date());
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load status");
    } finally {
      setLoading(false);
      if (manual) setIsRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void load();
    const interval = setInterval(() => void load(), 5000);
    return () => clearInterval(interval);
  }, [load]);

  const refresh = useCallback(() => load(true), [load]);

  return { tachikomas, queue, loading, isRefreshing, lastRefreshed, error, refresh };
}
