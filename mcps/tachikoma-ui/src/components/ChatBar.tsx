import { useEffect, useRef, useState } from "react";
import type { ActionEvent, ChatMessage } from "@/types";
import {
  openChatStream,
  dispatch,
  stopTachikoma,
  abandonTachikoma,
  createWorkRequest,
  deleteWorkRequest,
} from "@/lib/api";

interface UiMessage extends ChatMessage {
  actions?: ActionEvent[];
}

const GREETING: UiMessage = {
  role: "assistant",
  content: "All systems online. Ghost: active. What are we building?",
};

export function ChatBar() {
  const [messages, setMessages] = useState<UiMessage[]>([GREETING]);
  const [input, setInput] = useState("");
  const [streaming, setStreaming] = useState(false);
  const listRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const cancelRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    const el = listRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [messages]);

  useEffect(() => {
    const ta = textareaRef.current;
    if (!ta) return;
    ta.style.height = "auto";
    const lineHeight = 20;
    const maxHeight = lineHeight * 3 + 16;
    ta.style.height = `${Math.min(ta.scrollHeight, maxHeight)}px`;
  }, [input]);

  useEffect(() => {
    return () => {
      cancelRef.current?.();
    };
  }, []);

  const runAction = async (action: ActionEvent) => {
    try {
      if (action.type === "dispatch") {
        await dispatch(action.cap);
      } else if (action.type === "stop") {
        await stopTachikoma(action.slug);
      } else if (action.type === "abandon") {
        await abandonTachikoma(action.slug);
      } else if (action.type === "create_work_request") {
        await createWorkRequest({
          slug: action.slug,
          target_repo: action.target_repo,
          goal: action.goal,
          stop_condition: action.stop_condition,
          quality_bar: action.quality_bar,
        });
      } else if (action.type === "delete_work_request") {
        await deleteWorkRequest(action.slug);
      }
    } catch (err) {
      console.error("[ChatBar] action error:", err);
    }
  };

  const send = () => {
    const trimmed = input.trim();
    if (!trimmed || streaming) return;

    const userMsg: UiMessage = { role: "user", content: trimmed };
    const nextMessages = [...messages, userMsg];
    const assistantMsg: UiMessage = { role: "assistant", content: "", actions: [] };

    setMessages([...nextMessages, assistantMsg]);
    setInput("");
    setStreaming(true);

    const chatHistory: ChatMessage[] = nextMessages.map((m) => ({
      role: m.role,
      content: m.content,
    }));

    const cancel = openChatStream(
      chatHistory,
      (token) => {
        setMessages((prev) => {
          const copy = [...prev];
          const last = copy[copy.length - 1];
          if (last && last.role === "assistant") {
            copy[copy.length - 1] = { ...last, content: last.content + token };
          }
          return copy;
        });
      },
      (action) => {
        setMessages((prev) => {
          const copy = [...prev];
          const last = copy[copy.length - 1];
          if (last && last.role === "assistant") {
            copy[copy.length - 1] = {
              ...last,
              actions: [...(last.actions ?? []), action],
            };
          }
          return copy;
        });
      },
      () => {
        setStreaming(false);
        cancelRef.current = null;
      },
      (msg) => {
        console.error("[ChatBar] stream error:", msg);
        setMessages((prev) => {
          const copy = [...prev];
          const last = copy[copy.length - 1];
          if (last && last.role === "assistant") {
            const errorText = last.content
              ? `${last.content}\n\n[error: ${msg}]`
              : `[error: ${msg}]`;
            copy[copy.length - 1] = { ...last, content: errorText };
          }
          return copy;
        });
        setStreaming(false);
        cancelRef.current = null;
      }
    );
    cancelRef.current = cancel;
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      send();
    }
  };

  const actionLabel = (action: ActionEvent): string => {
    if (action.type === "dispatch") return `Dispatch (cap ${action.cap})`;
    if (action.type === "stop") return `Stop ${action.slug}`;
    if (action.type === "abandon") return `Abandon ${action.slug}`;
    if (action.type === "create_work_request") return `Create request: ${action.slug}`;
    if (action.type === "delete_work_request") return `Delete ${action.slug}`;
    return "";
  };

  return (
    <div className="fixed bottom-0 left-0 right-0 bg-zinc-900 border-t border-zinc-800 z-40 flex flex-col">
      <div
        ref={listRef}
        className="flex-1 overflow-y-auto max-h-[160px] px-6 py-3 flex flex-col gap-2"
      >
        {messages.map((m, i) => (
          <div
            key={i}
            className={`flex flex-col gap-1.5 ${
              m.role === "user" ? "items-end" : "items-start"
            }`}
          >
            <div
              className={
                m.role === "user"
                  ? "bg-zinc-800 rounded-lg px-3 py-2 text-sm text-zinc-100 max-w-[80%] whitespace-pre-wrap"
                  : "text-zinc-100 text-sm max-w-[80%] whitespace-pre-wrap"
              }
            >
              {m.content || (streaming && i === messages.length - 1 ? "…" : "")}
            </div>
            {m.role === "assistant" && m.actions && m.actions.length > 0 && (
              <div className="flex flex-wrap gap-2">
                {m.actions.map((a, j) => (
                  <button
                    key={j}
                    onClick={() => void runAction(a)}
                    className="bg-zinc-700 hover:bg-zinc-600 text-zinc-100 text-xs px-3 py-1.5 rounded transition-colors"
                  >
                    {actionLabel(a)}
                  </button>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>

      <div className="flex items-end gap-2 px-6 py-3 border-t border-zinc-800">
        <textarea
          ref={textareaRef}
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="What do you want to build?"
          rows={1}
          className="flex-1 resize-none bg-zinc-950 border border-zinc-800 rounded px-3 py-2 text-sm text-zinc-100 placeholder-zinc-600 font-mono focus:outline-none focus:border-zinc-600 leading-5"
        />
        <button
          onClick={send}
          disabled={streaming || !input.trim()}
          className="flex-shrink-0 h-9 px-4 rounded bg-zinc-700 hover:bg-zinc-600 disabled:opacity-40 disabled:cursor-not-allowed text-zinc-100 text-sm font-medium transition-colors flex items-center justify-center"
        >
          {streaming ? (
            <svg
              className="animate-spin h-4 w-4 text-zinc-100"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
            >
              <circle
                className="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                strokeWidth="4"
              />
              <path
                className="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z"
              />
            </svg>
          ) : (
            "Send"
          )}
        </button>
      </div>
    </div>
  );
}
