import React from 'react';
import {Pressable, ScrollView, StyleSheet, Text, TextInput, useWindowDimensions, View} from 'react-native';
import {isDiaryDate, localDate, shiftDate} from '@prelis/core';
import {Button, colors, Section, styles} from '../../shared/ui';
import {Icon} from '../../shared/icon';

type Props = {
  date: string;
  month: string;
  content: string;
  dirty: boolean;
  everSaved: boolean;
  loading: boolean;
  saving: boolean;
  error: string;
  onContent: (content: string) => void;
  onDate: (date: string) => void;
  onMonth: (delta: number) => void;
  onRetry: () => void;
  onSave: () => Promise<void>;
};

const heading = (date: string) => `${Number(date.slice(0, 4))}年${Number(date.slice(5, 7))}月${Number(date.slice(8, 10))}日`;

export function DiaryView({date, month, content, dirty, everSaved, loading, saving, error, onContent, onDate, onMonth, onRetry, onSave}: Props) {
  const {width: screenWidth} = useWindowDimensions();
  const calendarWidth = {width: Math.max(308, screenWidth - 48)};
  const first = `${month}-01`;
  const offset = (new Date(`${first}T12:00:00`).getDay() + 6) % 7;
  const days = Array.from({length: 42}, (_, i) => shiftDate(first, i - offset));
  return <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
    <View style={styles.pageIntro}><Text style={styles.heading}>Diary</Text><View style={styles.emblem}><Icon name="diary" size={29} color={colors.accent} /></View></View>
    <Section title={heading(date)}>
      <Text style={styles.muted}>{date === localDate() ? '今日' : date}</Text>
      <View style={[styles.row, diaryStyles.wrap]}>
        <Button label="前日" icon="left" disabled={saving || !isDiaryDate(shiftDate(date, -1))} onPress={() => onDate(shiftDate(date, -1))} />
        <Button label="翌日" icon="right" disabled={saving || !isDiaryDate(shiftDate(date, 1))} onPress={() => onDate(shiftDate(date, 1))} />
        <Button label="今日へ" disabled={saving || date === localDate()} onPress={() => onDate(localDate())} />
      </View>
    </Section>
    {loading ? <Text style={styles.muted}>日記を読み込んでいます…</Text> : error && !dirty ? <Section title="日記を開けませんでした"><Text style={styles.error}>{error}</Text><Button label="もう一度読み込む" onPress={onRetry} /></Section> : <Section title="日記の本文">
      <TextInput testID="diary-content" accessibilityLabel="日記の本文" style={[styles.input, diaryStyles.editor]} multiline value={content} editable={!saving} onChangeText={onContent} />
      <Text style={styles.muted}>{[...content].length.toLocaleString()} 文字　{saving ? '保存中…' : dirty ? '未保存' : everSaved ? '保存済み' : '変更なし'}</Text>
      <Button label={saving ? '保存中…' : '保存'} disabled={saving || !dirty} variant="primary" icon="save" onPress={onSave} />
      {!!error && <Text style={styles.error}>{error}</Text>}
      <Text style={styles.muted}>保存先: このデバイス</Text>
    </Section>}
    <Section title={`${Number(month.slice(0, 4))}年${Number(month.slice(5, 7))}月`}>
      <View style={styles.row}><Button label="前の月" icon="left" onPress={() => onMonth(-1)} /><Button label="次の月" icon="right" onPress={() => onMonth(1)} /></View>
      <ScrollView horizontal showsHorizontalScrollIndicator={false}>
        <View style={[diaryStyles.calendar, calendarWidth]}>
          {['月','火','水','木','金','土','日'].map(day => <Text key={day} style={diaryStyles.weekday}>{day}</Text>)}
          {days.map(day => <View key={day} style={diaryStyles.day}>{day.slice(0, 7) === month ?
            <Pressable accessibilityRole="button" accessibilityLabel={`${day}${day === localDate() ? ' 今日' : ''}の日記`} accessibilityState={{selected: date === day, disabled: saving || loading || !!error && !dirty}} disabled={saving || loading || !!error && !dirty} onPress={() => onDate(day)} style={({pressed}) => [diaryStyles.dayButton, date === day && diaryStyles.daySelected, day === localDate() && diaryStyles.dayToday, pressed && diaryStyles.dayPressed]}>
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
