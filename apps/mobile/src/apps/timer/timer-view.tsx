import React, {useState} from 'react';
import {ScrollView, StyleSheet, Text, TextInput, View} from 'react-native';
import type {SoundLibrary} from './sound-storage';
import {Button, colors, Page, Section, styles} from '../../shared/ui';
import {Icon} from '../../shared/icon';
import {TimerRing} from './timer-ring';

type Props = {
  minutes: string;
  valid: boolean;
  remaining: number;
  running: boolean;
  library: SoundLibrary | null;
  error: string;
  busy: boolean;
  onMinutes: (minutes: string) => void;
  onToggle: () => void;
  onReset: () => void;
  onRetry: () => void;
  onSelectSound: (id: string | null) => Promise<void>;
  onAddSound: () => Promise<void>;
  onPreviewSound: (id: string) => void;
  onDeleteSound: (id: string) => Promise<void>;
};

export function TimerView({minutes, valid, remaining, running, library, error, busy, onMinutes, onToggle, onReset, onRetry, onSelectSound, onAddSound, onPreviewSound, onDeleteSound}: Props) {
  const [soundOpen, setSoundOpen] = useState(false);
  const [ringSize, setRingSize] = useState(160);
  const completed = remaining === 0;
  const selected = library?.sounds.find(sound => sound.id === library.selectedId);
  const seconds = Math.ceil(remaining / 1000);
  const total = valid ? Number(minutes) * 60 * 1000 : remaining;
  const progress = total > 0 ? Math.max(0, Math.min(100, remaining / total * 100)) : 0;
  return <Page id="timer" contentStyle={timerStyles.content}>
    <View style={styles.pageIntro}><Text style={styles.heading}>Timer</Text><View style={styles.emblem}><Icon name="timer" size={22} color={colors.accent} /></View></View>
    <View style={timerStyles.clockArea} onLayout={({nativeEvent: {layout}}) => setRingSize(Math.max(160, Math.min(280, Math.floor(layout.width), Math.floor(layout.height))))}>
      <View style={timerStyles.ringArea}>
        <TimerRing size={ringSize} progress={progress} completed={completed}>
          <Text testID="timer-clock" accessibilityRole="timer" accessibilityLabel="残り時間" style={[timerStyles.clock, {fontSize: ringSize * 0.21, lineHeight: ringSize * 0.26}, running && timerStyles.running, completed && timerStyles.completed]}>
            {String(Math.floor(seconds / 60)).padStart(2, '0')}<Text style={[timerStyles.colon, completed && timerStyles.completed]}>:</Text>{String(seconds % 60).padStart(2, '0')}
          </Text>
          <Text style={[styles.caption, timerStyles.center, completed && timerStyles.completed]}>{completed ? '完了\nリセットしてください' : running ? '実行中' : '停止中'}</Text>
        </TimerRing>
      </View>
    </View>
    <View style={timerStyles.minuteRow}>
      <Text style={styles.text}>時間（分）</Text>
      <TextInput accessibilityLabel="時間（分）" keyboardType="number-pad" style={[styles.input, timerStyles.minuteInput]} value={minutes} editable={!running && !completed} onChangeText={onMinutes} />
    </View>
    {!valid && <Text style={styles.error}>1〜180の整数を入力してください。</Text>}
    <View style={styles.row}>
      <Button label={running ? '一時停止' : '開始'} variant="primary" icon={!running ? 'arrow' : undefined} disabled={completed || !running && (!valid || !library || busy)} onPress={onToggle} />
      <Button label="リセット" onPress={onReset} />
    </View>
    <View style={timerStyles.soundRow}>
      <View style={timerStyles.soundSummary}>
        <Text style={styles.caption}>終了音</Text>
        <Text style={styles.muted} numberOfLines={2}>{selected?.name ?? 'なし'}</Text>
      </View>
      <Button label={soundOpen ? '音声設定を閉じる' : '音声設定を開く'} expanded={soundOpen} onPress={() => setSoundOpen(value => !value)} />
    </View>
    {!!error && <ScrollView style={timerStyles.error} nestedScrollEnabled><Text style={styles.error}>{error}</Text></ScrollView>}
    <Text style={styles.caption}>バックグラウンドの終了音は保証されません。{'\n'}アプリ終了時にリセットされます。</Text>
    {soundOpen && <Section title="音声設定">
      {!library ? <Button label="再読み込み" onPress={onRetry} /> : <>
        <Text style={styles.muted}>音声を選択</Text>
        <Button label="音声なし" icon={!library.selectedId ? 'check' : undefined} variant="choice" selected={!library.selectedId} disabled={busy || running || completed} onPress={() => onSelectSound(null)} />
        {library.sounds.map(sound => <Button key={sound.id} label={sound.name} icon={library.selectedId === sound.id ? 'check' : undefined} variant="choice" selected={library.selectedId === sound.id} disabled={busy || running || completed} onPress={() => onSelectSound(sound.id)} />)}
        <Button label="音声を追加（MP3 / WAV、10 MB 以下）" disabled={busy || running || completed} onPress={onAddSound} />
        <View style={[styles.row, timerStyles.wrap]}>
          <Button label="試聴" disabled={!selected || busy || running || completed} onPress={() => {if (selected) onPreviewSound(selected.id);}} />
          <Button label="選択中の音声を削除" variant="danger" disabled={!selected || busy || running || completed} onPress={() => {if (selected) onDeleteSound(selected.id);}} />
        </View>
      </>}
    </Section>}
  </Page>;
}

const timerStyles = StyleSheet.create({
  content: {gap: 6},
  clockArea: {flexGrow: 1, minHeight: 160},
  ringArea: {position: 'absolute', inset: 0, alignItems: 'center', justifyContent: 'center'},
  clock: {fontWeight: '300', fontVariant: ['tabular-nums'], letterSpacing: -1, color: '#456b83', textAlign: 'center'},
  colon: {color: '#acd3e6'},
  running: {color: '#26769c'},
  minuteRow: {flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 8},
  minuteInput: {width: 100, textAlign: 'center'},
  soundRow: {flexDirection: 'row', alignItems: 'center', gap: 8},
  soundSummary: {flex: 1},
  error: {maxHeight: 60},
  completed: {color: '#a5453f'},
  center: {textAlign: 'center'},
  wrap: {flexWrap: 'wrap'},
});
