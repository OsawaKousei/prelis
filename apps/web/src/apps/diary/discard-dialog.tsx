import { useEffect, useRef } from 'react';
export const DiscardDialog = ({
  onCancel,
  onDiscard,
}: {
  readonly onCancel: () => void;
  readonly onDiscard: () => void;
}) => {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    dialog?.showModal();
    return () => dialog?.close();
  }, []);
  return (
    <dialog
      ref={ref}
      aria-labelledby="discard-title"
      onCancel={(event) => {
        event.preventDefault();
        onCancel();
      }}
    >
      <h2 id="discard-title">未保存の変更があります</h2>
      <p>変更を破棄しますか？入力内容は保存されません。</p>
      <div className="dialog-actions">
        <button autoFocus onClick={onCancel}>
          キャンセル
        </button>
        <button className="danger-button" onClick={onDiscard}>
          変更を破棄
        </button>
      </div>
    </dialog>
  );
};
