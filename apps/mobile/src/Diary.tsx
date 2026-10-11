import React, {useCallback, useEffect, useState} from 'react';
import {Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, useWindowDimensions, View} from 'react-native';
import {isDiaryDate, localDate, shiftDate} from '@prelis/core';
import {native} from './native';
import {Button, colors, Section, styles} from './ui';
import {Icon} from './icon';

type Props = {onState: (dirty: boolean, saving: boolean) => void};
const heading = (date: string) => `${Number(date.slice(0, 4))}年${Number(date.slice(5, 7))}月${Number(date.slice(8, 10))}日`;

export function Diary({onState}: Props) {
  const {width: screenWidth} = useWindowDimensions();
  const calendarWidth = {width: Math.max(308, screenWidth - 48)};
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
    <View style={styles.pageIntro}><Text style={styles.heading}>Diary</Text><View style={styles.emblem}><Icon name="diary" size={29} color={colors.accent} /></View></View>
    <Section title={heading(date)}>
      <Text style={styles.muted}>{date === localDate() ? '今日' : date}</Text>
      <View style={[styles.row, diaryStyles.wrap]}>
        <Button label="前日" icon="left" disabled={saving || !isDiaryDate(shiftDate(date, -1))} onPress={() => move(shiftDate(date, -1))} />
        <Button label="翌日" icon="right" disabled={saving || !isDiaryDate(shiftDate(date, 1))} onPress={() => move(shiftDate(date, 1))} />
        <Button label="今日へ" disabled={saving || date === localDate()} onPress={() => move(localDate())} />
      </View>
    </Section>
    {loading ? <Text style={styles.muted}>日記を読み込んでいます…</Text> : error && !dirty ? <Section title="日記を開けませんでした"><Text style={styles.error}>{error}</Text><Button label="もう一度読み込む" onPress={() => setRetry(value => value + 1)} /></Section> : <Section title="日記の本文">
      <TextInput testID="diary-content" accessibilityLabel="日記の本文" style={[styles.input, diaryStyles.editor]} multiline value={content} editable={!saving} onChangeText={setContent} />
      <Text style={styles.muted}>{[...content].length.toLocaleString()} 文字　{saving ? '保存中…' : dirty ? '未保存' : everSaved ? '保存済み' : '変更なし'}</Text>
      <Button label={saving ? '保存中…' : '保存'} disabled={saving || !dirty} variant="primary" icon="save" onPress={async () => {
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
      <View style={styles.row}><Button label="前の月" icon="left" onPress={() => shiftMonth(-1)} /><Button label="次の月" icon="right" onPress={() => shiftMonth(1)} /></View>
      <ScrollView horizontal showsHorizontalScrollIndicator={false}>
        <View style={[diaryStyles.calendar, calendarWidth]}>
          {['月','火','水','木','金','土','日'].map(day => <Text key={day} style={diaryStyles.weekday}>{day}</Text>)}
          {days.map(day => <View key={day} style={diaryStyles.day}>{day.slice(0, 7) === month ?
            <Pressable accessibilityRole="button" accessibilityLabel={`${day}${day === localDate() ? ' 今日' : ''}の日記`} accessibilityState={{selected: date === day, disabled: saving || loading || !!error && !dirty}} disabled={saving || loading || !!error && !dirty} onPress={() => move(day)} style={({pressed}) => [diaryStyles.dayButton, date === day && diaryStyles.daySelected, day === localDate() && diaryStyles.dayToday, pressed && diaryStyles.dayPressed]}>
              <Text style={[diaryStyles.dayLabel, date === day && diaryStyles.daySelectedLabel]}>{Number(day.slice(-2))}</Text>
            </Pressable> : null}</View>)}
        </View>
      </ScrollView>
    </Section>
  </ScrollView>;
}

const diaryStyles = StyleSheet.create({
  wrap: {flexWrap: 'wrap'},
  editor: {minHeight: 220, textAlignVertical: 'top'},
  calendar: {flexDirection: 'row', flexWrap: 'wrap'},
  weekday: {width: '14.2857%', textAlign: 'center', color: colors.muted, fontSize: 12, paddingBottom: 10},
  day: {width: '14.2857%', alignItems: 'center', paddingVertical: 2},
  dayButton: {width: 44, height: 44, alignItems: 'center', justifyContent: 'center', borderRadius: 22},
  daySelected: {backgroundColor: colors.accentSoft},
  dayToday: {borderWidth: 1, borderColor: colors.accentLine},
  dayPressed: {opacity: 0.65},
  dayLabel: {fontSize: 15, color: colors.ink},
  daySelectedLabel: {color: colors.accent, fontWeight: '700'},
});
