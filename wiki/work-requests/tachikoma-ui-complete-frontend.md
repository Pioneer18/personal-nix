---
status: open
target_repo: ~/projects/personal-nix
github_issue: ""
failure_count: 0
last_updated: 2026-05-11
---

# Tachikoma UI — Complete Frontend

Write the 5 missing frontend files that complete the Tachikoma local web UI.

## Goal

The Tachikoma UI is a single-page React app at `mcps/tachikoma-ui/` that monitors and controls autonomous coding runs. The backend, types, hooks, and most components are already written. This work request completes the remaining 5 files so the app is fully functional and builds cleanly.

## Context

The following files already exist and must NOT be modified:

- `mcps/tachikoma-ui/package.json` — Vite + React + Express + Radix UI + Tailwind
- `mcps/tachikoma-ui/tsconfig.json`, `vite.config.ts`, `tailwind.config.ts`, `postcss.config.js`
- `mcps/tachikoma-ui/index.html` — has `<div id="root">` entry point
- `mcps/tachikoma-ui/src/types.ts` — TachikomaState, WorkQueueItem, ChatMessage, ActionEvent, BmoFace, TachikomaStatus
- `mcps/tachikoma-ui/src/lib/api.ts` — fetchStatus, fetchQueue, postStop, postAbandon, postCleanup, postDispatch
- `mcps/tachikoma-ui/src/hooks/useStatus.ts` — polls /api/status + /api/queue every 5s
- `mcps/tachikoma-ui/src/hooks/useLogStream.ts` — SSE connection to /api/logs/:slug
- `mcps/tachikoma-ui/src/components/TachikomaCard.tsx` — card with BMO face, status badge, action buttons
- `mcps/tachikoma-ui/src/components/ActiveCards.tsx` — grid of TachikomaCard
- `mcps/tachikoma-ui/src/components/WorkQueue.tsx` — list of work queue items
- `mcps/tachikoma-ui/src/components/StopModal.tsx` — Radix Dialog for stop confirmation
- `mcps/tachikoma-ui/src/components/AbandonModal.tsx` — Radix Dialog, 2-step confirmation
- `mcps/tachikoma-ui/src/components/CleanupModal.tsx` — Radix Dialog for stale cleanup

## Files to write

1. `mcps/tachikoma-ui/src/index.css`
2. `mcps/tachikoma-ui/src/main.tsx`
3. `mcps/tachikoma-ui/src/App.tsx`
4. `mcps/tachikoma-ui/src/components/LogDrawer.tsx`
5. `mcps/tachikoma-ui/src/components/ChatBar.tsx`

## Design spec for each file

### `src/index.css`
Tailwind directives only:
```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```
Plus a dark base: `html { background: #09090b; }` (zinc-950 equivalent).
Custom scrollbar styling for dark theme (webkit scrollbar: thin, zinc-700 thumb).

### `src/main.tsx`
Standard React 18 entry — creates root, sets `document.documentElement.classList.add("dark")`, renders `<App />` into `#root`.

### `src/App.tsx`
Single-page layout, full viewport height (`h-screen`), flex column, `bg-zinc-950 text-zinc-100`:

```
┌──────────────────────────────────────────────────────┐
│  header: "Tachikoma" (left) + polling indicator      │
├─────────────────────────────┬────────────────────────┤
│  Main content               │  LogDrawer panel       │
│  (flex-1, overflow-y-auto)  │  (fixed right, ~40vw,  │
│                             │  full height, visible  │
│  - <WorkQueue />            │  when selectedSlug     │
│  - <ActiveCards />          │  is set)               │
│                             │                        │
├─────────────────────────────┴────────────────────────┤
│  <ChatBar /> (fixed bottom, ~220px)                  │
└──────────────────────────────────────────────────────┘
```

App state:
- `selectedSlug: string | null` — which tachikoma's log drawer is open
- Pass `onCardClick(slug)` to ActiveCards → TachikomaCard
- Pass `onClose()` to LogDrawer
- `useStatus()` hook drives data for WorkQueue + ActiveCards
- LogDrawer receives `slug={selectedSlug}` and uses `useLogStream(slug)` internally

### `src/components/LogDrawer.tsx`
Props: `{ slug: string | null; onClose: () => void; tachikomas: TachikomaState[] }`

When `slug` is null: render nothing (or hidden via CSS).

When `slug` is set:
- Fixed right panel: `fixed top-0 right-0 h-full w-[40vw] bg-zinc-900 border-l border-zinc-800 z-50 flex flex-col`
- Header (height ~64px): BMO face PNG (`<img src="/api/bmo/${state.bmoFace}.png" className="h-10 w-10 object-contain" />`), slug name, status badge, × close button (top-right, `aria-label="Close log drawer"`)
- Log area: `flex-1 overflow-hidden` wrapping a `<ScrollArea>` from `@radix-ui/react-scroll-area`
  - Inner: `<pre className="font-mono text-xs text-zinc-300 whitespace-pre-wrap p-4">` with all log lines joined by `\n`
  - Auto-scroll to bottom when new lines arrive (use `useEffect` on lines.length, scrolling the ScrollArea viewport)
- Footer (height ~32px): connection status — "● Streaming" (green) when connected, "◌ Reconnecting..." (amber) when not
- Close on Escape key via `useEffect` with keydown listener

Uses `useLogStream(slug)` hook.

If tachikoma not found for slug: show "Run not found" in the drawer body.

### `src/components/ChatBar.tsx`
Props: none (manages its own state)

Fixed bottom bar: `fixed bottom-0 left-0 right-0 bg-zinc-900 border-t border-zinc-800 z-40`
Height: auto, min ~220px.

Internal state:
- `messages: Array<{role: "user"|"assistant", content: string, actions?: ActionEvent[]}>` — starts with one assistant greeting: `"All systems online. Ghost: active. What are we building?"`
- `input: string`
- `streaming: boolean`

Message list:
- Scrollable area above input, newest at bottom
- User messages: right-aligned, `bg-zinc-800 rounded-lg px-3 py-2 text-sm`
- Assistant messages: left-aligned, `text-zinc-100 text-sm`
- After each assistant message: render action buttons for any `actions` on that message
  - Action button styles: `bg-zinc-700 hover:bg-zinc-600 text-zinc-100 text-xs px-3 py-1.5 rounded`
  - Action types:
    - `{ type: "dispatch", cap: N }` → button label `"Dispatch (cap ${N})"` → calls `postDispatch(N)` then adds success message
    - `{ type: "stop", slug }` → button label `"Stop ${slug}"` → opens StopModal (or calls postStop directly if you want to keep it simple here)
    - `{ type: "abandon", slug }` → button label `"Abandon ${slug}"` → adds to state for parent to handle

Streaming: POST to `/api/chat` with `{ messages }`, read SSE response:
- `data: <token>` events → append to current assistant message (streaming)
- `event: action` events → parse JSON, append to actions array of current message

Input area:
- `<textarea>` — placeholder "What do you want to build?", auto-resize (max 3 rows), Enter sends (Shift+Enter = newline)
- Send button: disabled while `streaming === true`, shows spinner SVG when streaming
- Both disabled while streaming

## Files in scope

- `mcps/tachikoma-ui/src/index.css`
- `mcps/tachikoma-ui/src/main.tsx`
- `mcps/tachikoma-ui/src/App.tsx`
- `mcps/tachikoma-ui/src/components/LogDrawer.tsx`
- `mcps/tachikoma-ui/src/components/ChatBar.tsx`

## Files out of scope

- `mcps/tachikoma-ui/server/**` — do not touch
- `mcps/tachikoma-ui/src/types.ts` — do not touch
- `mcps/tachikoma-ui/src/lib/api.ts` — do not touch
- `mcps/tachikoma-ui/src/hooks/**` — do not touch
- `mcps/tachikoma-ui/src/components/TachikomaCard.tsx` — do not touch
- `mcps/tachikoma-ui/src/components/ActiveCards.tsx` — do not touch
- `mcps/tachikoma-ui/src/components/WorkQueue.tsx` — do not touch
- `mcps/tachikoma-ui/src/components/StopModal.tsx` — do not touch
- `mcps/tachikoma-ui/src/components/AbandonModal.tsx` — do not touch
- `mcps/tachikoma-ui/src/components/CleanupModal.tsx` — do not touch
- `mcps/tachikoma-ui/package.json`, `tsconfig.json`, `vite.config.ts`, `tailwind.config.ts`, `postcss.config.js`, `index.html` — do not touch

## Stop condition

1. `mcps/tachikoma-ui/src/index.css` exists with Tailwind directives and dark scrollbar styles
2. `mcps/tachikoma-ui/src/main.tsx` exists, mounts React 18 root into `#root`, sets `dark` class on `<html>`
3. `mcps/tachikoma-ui/src/App.tsx` exists, imports and composes WorkQueue + ActiveCards + LogDrawer + ChatBar into the layout described above
4. `mcps/tachikoma-ui/src/components/LogDrawer.tsx` exists with right-panel layout, ScrollArea, auto-scroll, Escape key handler, BMO face img, and SSE streaming via `useLogStream`
5. `mcps/tachikoma-ui/src/components/ChatBar.tsx` exists with message history, streaming POST /api/chat, action button detection, and textarea input
6. `cd mcps/tachikoma-ui && npx tsc --noEmit` exits 0 (after running `npm install` first)
7. `cd mcps/tachikoma-ui && npm run build` exits 0 (Vite build produces `dist/`)

## Feedback loops

- `cd mcps/tachikoma-ui && npm install` (first time only)
- `cd mcps/tachikoma-ui && npx tsc --noEmit`
- `cd mcps/tachikoma-ui && npm run build`

## Quality bar

Prototype — this is a personal local tool. Speed over perfection. No tests required. TypeScript must pass (`tsc --noEmit`) and the Vite build must succeed.
