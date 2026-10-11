import { useState } from 'react';
import { Icon } from '../../shared/icon';
import { localDate, shiftDate } from './diary';
type Props = {
  readonly date: string;
  readonly today: string;
  readonly disabled: boolean;
  readonly onSelect: (date: string) => void;
};
export const Calendar = ({ date, today, disabled, onSelect }: Props) => {
  const [month, setMonth] = useState(date.slice(0, 7));
  const first = `${month}-01`;
  const offset = (new Date(`${first}T12:00:00`).getDay() + 6) % 7;
  const nextMonth = (delta: number) => {
    const next = new Date(`${first}T12:00:00`);
    next.setMonth(next.getMonth() + delta);
    if (next.getFullYear() >= 1 && next.getFullYear() <= 9999)
      setMonth(localDate(next).slice(0, 7));
  };
  const days = Array.from({ length: 42 }, (_, index) =>
    shiftDate(first, index - offset),
  );
  return (
    <section className="calendar" aria-label="日記のカレンダー">
      <div className="calendar-heading">
        <h3>
          {new Intl.DateTimeFormat('ja-JP', {
            year: 'numeric',
            month: 'long',
          }).format(new Date(`${first}T12:00:00`))}
        </h3>
        <div>
          <button
            className="icon-button"
            aria-label="前の月"
            onClick={() => nextMonth(-1)}
          >
            <Icon name="left" size={16} />
          </button>
          <button
            className="icon-button"
            aria-label="次の月"
            onClick={() => nextMonth(1)}
          >
            <Icon name="right" size={16} />
          </button>
        </div>
      </div>
      <div className="calendar-grid">
        {['月', '火', '水', '木', '金', '土', '日'].map((day) => (
          <span className="weekday-label" key={day}>
            {day}
          </span>
        ))}
        {days.map((day) =>
          day.slice(0, 7) === month ? (
            <button
              key={day}
              disabled={disabled}
              aria-label={`${day}の日記`}
              aria-pressed={date === day}
              aria-current={day === today ? 'date' : undefined}
              className={`${date === day ? 'chosen' : ''} ${day === today ? 'today' : ''}`}
              onClick={() => onSelect(day)}
            >
              {Number(day.slice(-2))}
            </button>
          ) : (
            <span key={day} />
          ),
        )}
      </div>
      <div className="calendar-legend">
        <span />
        今日
      </div>
    </section>
  );
};
