export type BmoFace =
  | "smile"
  | "content"
  | "neutral"
  | "angry"
  | "disbelief"
  | "frustrated"
  | "out-of-wack";

export type TachikomaStatus =
  | "running"
  | "complete"
  | "cap"
  | "error"
  | "stopped"
  | "unknown"
  | "stale";

export interface TachikomaState {
  repo: string;
  branch: string;
  worktree: string;
  slug: string;
  status: TachikomaStatus;
  pid: number | null;
  iter: string | null;
  lastProgress: string | null;
  bmoFace: BmoFace;
}

export interface WorkQueueItem {
  slug: string;
  status: "open" | "grabbed" | "done";
  targetRepo: string;
  priority: number;
  goal: string;
  qualityBar: string;
  activeBranch: string | null;
}

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export type ActionEvent =
  | { type: "dispatch"; cap: number }
  | { type: "stop"; slug: string }
  | { type: "abandon"; slug: string };
