import React, {useCallback, useEffect, useState} from 'react';
import {Alert, ScrollView, StyleSheet, Text, TextInput, View} from 'react-native';
import {isDiaryDate, localDate, shiftDate} from '@prelis/core';
import {native} from './native';
import {Button, colors, Section, styles} from './ui';

type Props = {onState: (dirty: boolean, saving: boolean) => void};
const heading = (date: string) => `${Number(date.slice(0, 4))}年${Number(date.slice(5, 7))}月${Number(date.slice(8, 10))}日`;

export function Diary({onState}: Props) {
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
    native.readDiary(date).then(text => {
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
  const offset = (new Date(`${first}T12:00:00`).getDay() + 6) % 7;
  const days = Array.from({length: 42}, (_, i) => shiftDate(first, i - offset));
  const shiftMonth = (delta: number) => {
    const next = new Date(`${first}T12:00:00`);
    next.setMonth(next.getMonth() + delta);
    if (next.getFullYear() >= 1 && next.getFullYear() <= 9999) setMonth(localDate(next).slice(0, 7));
  };
  return <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
    <Text style={styles.heading}>Diary</Text>
    <Section title={heading(date)}>
      <Text style={styles.muted}>{date === localDate() ? '今日' : date}</Text>
      <View style={[styles.row, diaryStyles.wrap]}>
        <Button label="前日" disabled={saving || !isDiaryDate(shiftDate(date, -1))} onPress={() => move(shiftDate(date, -1))} />
        <Button label="翌日" disabled={saving || !isDiaryDate(shiftDate(date, 1))} onPress={() => move(shiftDate(date, 1))} />
        <Button label="今日へ" disabled={saving || date === localDate()} onPress={() => move(localDate())} />
      </View>
    </Section>
    {loading ? <Text style={styles.muted}>日記を読み込んでいます…</Text> : error && !dirty ? <Section title="日記を開けませんでした"><Text style={styles.error}>{error}</Text><Button label="もう一度読み込む" onPress={() => setRetry(value => value + 1)} /></Section> : <Section title="日記の本文">
      <TextInput testID="diary-content" accessibilityLabel="日記の本文" style={[styles.input, diaryStyles.editor]} multiline value={content} editable={!saving} onChangeText={setContent} />
      <Text style={styles.muted}>{[...content].length.toLocaleString()} 文字　{saving ? '保存中…' : dirty ? '未保存' : everSaved ? '保存済み' : '変更なし'}</Text>
      <Button label={saving ? '保存中…' : '保存'} disabled={saving || !dirty} selected onPress={async () => {
        const text = content;
        setSaving(true); setError('');
        try {await native.saveDiary(date, text); setSaved(text); setEverSaved(true);}
        catch {setError('保存できませんでした。入力内容は保持されています。再試行してください。');}
        finally {setSaving(false);}
      }} />
      {!!error && <Text style={styles.error}>{error}</Text>}
      <Text style={styles.muted}>保存先: このデバイス</Text>
    </Section>}
    <Section title={`${Number(month.slice(0, 4))}年${Number(month.slice(5, 7))}月`}>
      <View style={styles.row}><Button label="前の月" onPress={() => shiftMonth(-1)} /><Button label="次の月" onPress={() => shiftMonth(1)} /></View>
      <View style={diaryStyles.calendar}>
        {['月','火','水','木','金','土','日'].map(day => <Text key={day} style={diaryStyles.weekday}>{day}</Text>)}
        {days.map(day => <View key={day} style={diaryStyles.day}>{day.slice(0, 7) === month ? <Button label={String(Number(day.slice(-2)))} selected={date === day} disabled={saving || loading || !!error && !dirty} onPress={() => move(day)} /> : null}</View>)}
      </View>
    </Section>
  </ScrollView>;
}

const diaryStyles = StyleSheet.create({
  wrap: {flexWrap: 'wrap'},
  editor: {minHeight: 220, textAlignVertical: 'top'},
  calendar: {flexDirection: 'row', flexWrap: 'wrap'},
  weekday: {width: '14.28%', textAlign: 'center', color: colors.muted},
  day: {width: '14.28%', padding: 2},
});
