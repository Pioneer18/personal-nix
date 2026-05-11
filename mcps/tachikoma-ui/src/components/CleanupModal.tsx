import * as Dialog from "@radix-ui/react-dialog";

interface CleanupModalProps {
  open: boolean;
  slug: string;
  onConfirm: () => void;
  onCancel: () => void;
}

export function CleanupModal({
  open,
  slug,
  onConfirm,
  onCancel,
}: CleanupModalProps) {
  return (
    <Dialog.Root open={open} onOpenChange={(v) => !v && onCancel()}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/60 z-40" />
        <Dialog.Content className="fixed left-1/2 top-1/2 z-50 -translate-x-1/2 -translate-y-1/2 w-full max-w-sm bg-zinc-900 border border-zinc-700 rounded-lg p-6 shadow-xl focus:outline-none">
          <Dialog.Title className="text-zinc-100 text-lg font-semibold mb-2">
            Clean up stale run?
          </Dialog.Title>
          <Dialog.Description className="text-zinc-400 text-sm mb-6">
            The Ghost for{" "}
            <span className="text-zinc-200 font-mono">{slug}</span> is gone.
            Delete the worktree?
          </Dialog.Description>
          <div className="flex gap-3 justify-end">
            <button
              onClick={onCancel}
              className="px-4 py-2 text-sm rounded-md bg-zinc-800 text-zinc-300 hover:bg-zinc-700 transition-colors"
            >
              Leave it
            </button>
            <button
              onClick={onConfirm}
              className="px-4 py-2 text-sm rounded-md bg-zinc-600 text-white hover:bg-zinc-500 transition-colors"
            >
              Clean up
            </button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
