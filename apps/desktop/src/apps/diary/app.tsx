import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { localDate, isDiaryDate } from './diary';
import { readDiary, saveDiary, isDesktop } from './storage';
import { DiaryView } from './diary-view';
import { DiscardDialog } from './discard-dialog';
import { useLeaveConfirmation } from './use-leave-confirmation';
import './diary.css';
const DiaryEditor = ({
  date,
  initialContent,
  onDate,
}: {
  readonly date: string;
  readonly initialContent: string;
  readonly onDate: (date: string) => void;
}) => {
  const [content, setContent] = useState(initialContent);
  const [savedContent, setSavedContent] = useState(initialContent);
  const client = useQueryClient();
  const dirty = content !== savedContent;
  const save = useMutation({
    mutationFn: (text: string) => saveDiary(date, text),
    onSuccess: (_result, text) => {
      setSavedContent(text);
      client.setQueryData(['diary', date], text);
    },
  });
  const leave = useLeaveConfirmation(dirty, save.isPending);
  const handleSave = () => {
    if (!dirty || save.isPending) return;
    save.mutate(content);
  };
  return (
    <>
      <DiaryView
        date={date}
        today={localDate()}
        content={content}
        dirty={dirty}
        saving={save.isPending}
        saved={save.isSuccess || initialContent.length > 0}
        error={save.isError}
        desktop={isDesktop}
        onChange={setContent}
        onDate={(next) => {
          if (next !== date && isDiaryDate(next))
            leave.requestLeave(() => onDate(next));
        }}
        onSave={handleSave}
      />
      {leave.closeError && (
        <p role="alert" className="error-message">
          ウィンドウの終了処理を設定できませんでした。終了する前に日記を保存してください。
        </p>
      )}
      {leave.pending && (
        <DiscardDialog onCancel={leave.cancel} onDiscard={leave.discard} />
      )}
    </>
  );
};
export const DiaryApp = () => {
  const [date, setDate] = useState(localDate);
  const entry = useQuery({
    queryKey: ['diary', date],
    queryFn: () => readDiary(date),
    gcTime: 0,
    staleTime: 0,
    refetchOnReconnect: false,
  });
  if (entry.isPending)
    return (
      <div className="resource-state" role="status">
        日記を読み込んでいます…
      </div>
    );
  if (entry.isError)
    return (
      <div className="resource-state">
        <h1>日記を開けませんでした</h1>
        <p role="alert">
          保存先にアクセスできません。日記は上書きされていません。
        </p>
        <button
          onClick={() => {
            void entry.refetch();
          }}
        >
          もう一度読み込む
        </button>
      </div>
    );
  return (
    <DiaryEditor
      key={date}
      date={date}
      initialContent={entry.data}
      onDate={setDate}
    />
  );
};
