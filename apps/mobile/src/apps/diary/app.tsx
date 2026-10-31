import React, {useCallback, useEffect, useState} from 'react';
import {Alert} from 'react-native';
import {isDiaryDate, localDate} from '@prelis/core';
import {readDiary, saveDiary} from './storage';
import {DiaryView} from './diary-view';

type Props = {onState: (dirty: boolean, saving: boolean) => void};

export function DiaryApp({onState}: Props) {
  const [date, setDate] = useState(localDate);
  const [month, setMonth] = useState(date.slice(0, 7));
  const [content, setContent] = useState('');
  const [saved, setSaved] = useState('');
  const [everSaved, setEverSaved] = useState(false);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [retry, setRetry] = useState(0);
  const dirty = content !== saved;
  useEffect(() => onState(dirty, saving), [dirty, saving, onState]);
  useEffect(() => {
    let active = true;
    setLoading(true); setError('');
    readDiary(date).then(text => {
      if (active) {setContent(text); setSaved(text); setEverSaved(text.length > 0); setLoading(false);}
    }).catch(() => {if (active) {setError('日記を開けませんでした。保存先にアクセスできません。'); setLoading(false);}});
    return () => {active = false;};
  }, [date, retry]);
  const move = useCallback((next: string) => {
    if (saving || !isDiaryDate(next) || next === date) return;
    const change = () => {setDate(next); setMonth(next.slice(0, 7));};
    if (dirty) Alert.alert('未保存の変更があります', '変更を破棄しますか？入力内容は保存されません。', [
      {text: 'キャンセル', style: 'cancel'}, {text: '変更を破棄', style: 'destructive', onPress: change},
    ]); else change();
  }, [date, dirty, saving]);
  const first = `${month}-01`;
  const shiftMonth = (delta: number) => {
    const next = new Date(`${first}T12:00:00`);
    next.setMonth(next.getMonth() + delta);
    if (next.getFullYear() >= 1 && next.getFullYear() <= 9999) setMonth(localDate(next).slice(0, 7));
  };
  return <DiaryView
    date={date} month={month} content={content} dirty={dirty}
    everSaved={everSaved} loading={loading} saving={saving} error={error}
    onContent={setContent} onDate={move} onMonth={shiftMonth}
    onRetry={() => setRetry(value => value + 1)}
    onSave={async () => {
      const text = content;
      setSaving(true); setError('');
      try {await saveDiary(date, text); setSaved(text); setEverSaved(true);}
      catch {setError('保存できませんでした。入力内容は保持されています。再試行してください。');}
      finally {setSaving(false);}
    }}
  />;
}
