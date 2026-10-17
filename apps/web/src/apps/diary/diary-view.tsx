import { Icon } from '../../shared/icon';
import { Calendar } from './calendar';
import { dateHeading, weekday, shiftDate, isDiaryDate } from './diary';
type Props = {
  readonly date: string;
  readonly today: string;
  readonly content: string;
  readonly dirty: boolean;
  readonly saving: boolean;
  readonly saved: boolean;
  readonly error: boolean;
  readonly onChange: (value: string) => void;
  readonly onDate: (date: string) => void;
  readonly onSave: () => void;
};
export const DiaryView = ({
  date,
  today,
  content,
  dirty,
  saving,
  saved,
  error,
  onChange,
  onDate,
  onSave,
}: Props) => (
  <div className="diary-workspace">
    <div className="diary-main">
      <div className="page-intro">
        <div>
          <h1>Diary</h1>
        </div>
        <span className="app-emblem" aria-hidden="true">
          <Icon name="diary" size={32} />
        </span>
      </div>
      <div className="date-toolbar">
        <div className="date-title">
          <h2>{dateHeading(date)}</h2>
          <span>
            {weekday(date)}
            {date === today && <span className="today-tag">今日</span>}
          </span>
        </div>
        <div className="date-actions">
          <button
            className="icon-button"
            disabled={saving || !isDiaryDate(shiftDate(date, -1))}
            aria-label="前日"
            onClick={() => onDate(shiftDate(date, -1))}
          >
            <Icon name="left" />
          </button>
          <button
            className="icon-button"
            disabled={saving || !isDiaryDate(shiftDate(date, 1))}
            aria-label="翌日"
            onClick={() => onDate(shiftDate(date, 1))}
          >
            <Icon name="right" />
          </button>
          <button
            disabled={saving || date === today}
            className="today-button"
            onClick={() => onDate(today)}
          >
            今日へ
          </button>
        </div>
      </div>
      <form
        className="editor"
        onSubmit={(event) => {
          event.preventDefault();
          onSave();
        }}
      >
        <label className="editor-label" htmlFor="diary-content">
          日記の本文
        </label>
        <textarea
          id="diary-content"
          value={content}
          disabled={saving}
          onChange={(event) => onChange(event.currentTarget.value)}
          spellCheck={false}
          onKeyDown={(event) => {
            if ((event.ctrlKey || event.metaKey) && event.key === 's') {
              event.preventDefault();
              onSave();
            }
          }}
        />
        <div className="editor-footer">
          <span className="character-count">
            {Array.from(content).length.toLocaleString()} <span>文字</span>
          </span>
          <div className="save-actions">
            <span role="status" className="save-status">
              {saving ? (
                '保存中…'
              ) : dirty ? (
                '未保存'
              ) : saved ? (
                <>
                  <Icon name="check" size={15} />
                  保存済み
                </>
              ) : (
                '変更なし'
              )}
            </span>
            <button
              type="submit"
              className="primary-button"
              disabled={saving || !dirty}
            >
              <Icon name="save" size={17} />
              {saving ? '保存中…' : '保存'}
            </button>
          </div>
        </div>
      </form>
      {error && (
        <p className="error-message" role="alert">
          保存できませんでした。入力内容は保持されています。保存先を確認して再試行してください。
        </p>
      )}
      <div className="diary-footnote">
        <span>保存先: このブラウザー（他のアプリと別データ）</span>
        <span>Ctrl / ⌘ + S で保存</span>
      </div>
    </div>
    <aside className="diary-aside">
      <Calendar
        key={`calendar-${date}`}
        date={date}
        today={today}
        disabled={saving}
        onSelect={onDate}
      />
    </aside>
  </div>
);
