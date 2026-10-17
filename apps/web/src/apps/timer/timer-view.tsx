import { Icon } from '../../shared/icon';
import type { SoundLibrary } from './sound-storage';
type Props = {
  readonly minutes: string;
  readonly validDuration: boolean;
  readonly remaining: number;
  readonly remainingMilliseconds: number;
  readonly running: boolean;
  readonly completed: boolean;
  readonly soundLibrary: SoundLibrary | null;
  readonly soundBusy: boolean;
  readonly soundReady: boolean;
  readonly soundError: string | null;
  readonly completionNotice: string | null;
  readonly onAddSound: (file: File) => void;
  readonly onSelectSound: (id: string | null) => void;
  readonly onDeleteSound: (id: string) => void;
  readonly onPreviewSound: () => void;
  readonly onRetrySounds: () => void;
  readonly onMinutes: (minutes: string) => void;
  readonly onToggle: () => void;
  readonly onReset: () => void;
};
export const TimerView = ({
  minutes,
  validDuration,
  remaining,
  remainingMilliseconds,
  running,
  completed,
  soundLibrary,
  soundBusy,
  soundReady,
  soundError,
  completionNotice,
  onAddSound,
  onSelectSound,
  onDeleteSound,
  onPreviewSound,
  onRetrySounds,
  onMinutes,
  onToggle,
  onReset,
}: Props) => {
  const totalMilliseconds = validDuration
    ? Number(minutes) * 60 * 1000
    : remainingMilliseconds;
  const progress =
    totalMilliseconds > 0
      ? Math.max(
          0,
          Math.min(100, (remainingMilliseconds / totalMilliseconds) * 100),
        )
      : 0;
  const selectedSoundName = soundLibrary
    ? (soundLibrary.sounds.find((sound) => sound.id === soundLibrary.selectedId)
        ?.name ?? 'なし')
    : '読み込み中…';

  return (
    <section className="timer-workspace">
      <div className="page-intro">
        <div>
          <h1>Timer</h1>
        </div>
        <span className="app-emblem">
          <Icon name="timer" size={32} />
        </span>
      </div>
      <div className="timer-layout">
        <div className="timer-center">
          <div className={`timer-ring${completed ? ' completed' : ''}`}>
            <svg
              className="timer-ring-graphic"
              viewBox="0 0 320 320"
              role="progressbar"
              aria-label="残り時間の割合"
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={Math.round(progress)}
            >
              <circle className="timer-ring-track" cx="160" cy="160" r="144" />
              <circle
                className="timer-ring-progress"
                cx="160"
                cy="160"
                r="144"
                pathLength="100"
                strokeDasharray="100"
                strokeDashoffset={100 - progress}
              />
            </svg>
            <div className="timer-ring-content">
              <div
                className={`timer-clock ${running ? 'running' : ''}`}
                role="timer"
                aria-label="残り時間"
              >
                {String(Math.floor(remaining / 60)).padStart(2, '0')}
                <span>:</span>
                {String(remaining % 60).padStart(2, '0')}
              </div>
              <p role="status">
                {completed
                  ? '完了 — リセットしてください'
                  : running
                    ? '実行中'
                    : '停止中'}
              </p>
            </div>
          </div>
          <label className="duration-input">
            時間（分）
            <input
              type="number"
              min="1"
              max="180"
              value={minutes}
              disabled={running || completed}
              aria-invalid={!validDuration}
              aria-describedby={!validDuration ? 'duration-error' : undefined}
              onChange={(event) => onMinutes(event.currentTarget.value)}
            />
          </label>
          {!validDuration && (
            <p id="duration-error" className="error-message">
              1〜180の整数を入力してください。
            </p>
          )}
          <div className="timer-actions">
            <button
              className="primary-button"
              disabled={
                completed ||
                (!running && (!validDuration || !soundReady || soundBusy))
              }
              onClick={onToggle}
            >
              {running ? '一時停止' : '開始'}
              <Icon name="arrow" size={18} />
            </button>
            <button onClick={onReset}>リセット</button>
          </div>
          <p className="timer-note">
            画面を切り替えても計時します。タブを閉じるとリセットされます。
            背景で完了した場合は戻ったときに表示します。終了音はブラウザーの設定によって再生できない場合があります。
          </p>
          {completionNotice && <p className="error-message" role="alert">{completionNotice}</p>}
          {completed && soundError && <p className="error-message" role="alert">{soundError}</p>}
        </div>
        <details className="timer-sound-settings">
          <summary>
            終了音: {selectedSoundName}
            {soundError && <span>（要確認）</span>}
          </summary>
          <div className="timer-sound-body">
            <div className="timer-sound-controls">
              <label>
                音声を選択
                <select
                  value={soundLibrary?.selectedId ?? ''}
                  disabled={
                    !soundLibrary ||
                    soundBusy ||
                    running ||
                    completed
                  }
                  onChange={(event) =>
                    onSelectSound(event.currentTarget.value || null)
                  }
                >
                  <option value="">音声なし</option>
                  {soundLibrary?.sounds.map((sound) => (
                    <option key={sound.id} value={sound.id}>
                      {sound.name}
                    </option>
                  ))}
                </select>
              </label>
              <label className="timer-sound-upload">
                音声を追加
                <input
                  type="file"
                  accept=".mp3,.wav,audio/mpeg,audio/wav"
                  disabled={
                    !soundLibrary ||
                    soundBusy ||
                    running ||
                    completed
                  }
                  onChange={(event) => {
                    const file = event.currentTarget.files?.[0];
                    if (file) onAddSound(file);
                    event.currentTarget.value = '';
                  }}
                />
              </label>
            </div>
            <p className="timer-sound-hint">MP3 / WAV、10 MB 以下</p>
            <div className="timer-sound-actions">
              <button
                disabled={
                  !soundLibrary?.selectedId ||
                  !soundReady ||
                  soundBusy ||
                  running ||
                  completed
                }
                onClick={onPreviewSound}
              >
                試聴
              </button>
              <button
                disabled={
                  !soundLibrary?.selectedId || soundBusy || running || completed
                }
                onClick={() => {
                  if (soundLibrary?.selectedId)
                    onDeleteSound(soundLibrary.selectedId);
                }}
              >
                選択中の音声を削除
              </button>
            </div>
            {!soundLibrary && !soundError && (
              <p className="timer-sound-hint">
                保存済みの音声を読み込んでいます…
              </p>
            )}
            {soundLibrary?.selectedId &&
              !soundReady &&
              !soundError && (
                <p className="timer-sound-hint">音声を準備しています…</p>
              )}
            {soundError && (
              <div className="timer-sound-error">
                <p role="alert">{soundError}</p>
                {!soundLibrary && (
                  <button onClick={onRetrySounds}>再読み込み</button>
                )}
              </div>
            )}
          </div>
        </details>
      </div>
    </section>
  );
};
