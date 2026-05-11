import { useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";

interface AbandonModalProps {
  open: boolean;
  slug: string;
  onConfirm: () => void;
  onCancel: () => void;
}

export function AbandonModal({
  open,
  slug,
  onConfirm,
  onCancel,
}: AbandonModalProps) {
  const [step, setStep] = useState<1 | 2>(1);

  const handleOpenChange = (v: boolean) => {
    if (!v) {
      setStep(1);
      onCancel();
    }
  };

  const handleContinue = () => setStep(2);

  const handleConfirm = () => {
    setStep(1);
    onConfirm();
  };

  const handleCancel = () => {
    setStep(1);
    onCancel();
  };

  return (
    <Dialog.Root open={open} onOpenChange={handleOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/60 z-40" />
        <Dialog.Content className="fixed left-1/2 top-1/2 z-50 -translate-x-1/2 -translate-y-1/2 w-full max-w-sm bg-zinc-900 border border-zinc-700 rounded-lg p-6 shadow-xl focus:outline-none">
          {step === 1 ? (
            <>
              <Dialog.Title className="text-zinc-100 text-lg font-semibold mb-2">
                Abandon this run?
              </Dialog.Title>
              <Dialog.Description className="text-zinc-400 text-sm mb-6">
                The worktree and branch for{" "}
                <span className="text-zinc-200 font-mono">{slug}</span> will be
                deleted. No PR will be opened.
              </Dialog.Description>
              <div className="flex gap-3 justify-end">
                <button
                  onClick={handleCancel}
                  className="px-4 py-2 text-sm rounded-md bg-zinc-800 text-zinc-300 hover:bg-zinc-700 transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={handleContinue}
                  className="px-4 py-2 text-sm rounded-md bg-zinc-700 text-zinc-100 hover:bg-zinc-600 transition-colors"
                >
                  Continue
                </button>
              </div>
            </>
          ) : (
            <>
              <Dialog.Title className="text-zinc-100 text-lg font-semibold mb-2">
                There's no going back.
              </Dialog.Title>
              <Dialog.Description className="text-zinc-400 text-sm mb-6">
                Delete the worktree and branch for{" "}
                <span className="text-zinc-200 font-mono">{slug}</span>{" "}
                permanently?
              </Dialog.Description>
              <div className="flex gap-3 justify-end">
                <button
                  onClick={handleCancel}
                  className="px-4 py-2 text-sm rounded-md bg-zinc-800 text-zinc-300 hover:bg-zinc-700 transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={handleConfirm}
                  className="px-4 py-2 text-sm rounded-md bg-red-700 text-white hover:bg-red-600 transition-colors"
                >
                  Delete worktree
                </button>
              </div>
            </>
          )}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
