import React, {useState} from 'react';
import {ScrollView, StyleSheet, Text, TextInput, View} from 'react-native';
import type {SoundLibrary} from './sound-storage';
import {Button, colors, Section, styles} from '../../shared/ui';
import {Icon} from '../../shared/icon';

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
  const completed = remaining === 0;
  const selected = library?.sounds.find(sound => sound.id === library.selectedId);
  const seconds = Math.ceil(remaining / 1000);
  const total = valid ? Number(minutes) * 60 * 1000 : remaining;
  const progress = total > 0 ? Math.max(0, Math.min(100, remaining / total * 100)) : 0;
  const progressWidth = {width: `${progress}%` as `${number}%`};
  return <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
    <View style={styles.pageIntro}><Text style={styles.heading}>Timer</Text><View style={styles.emblem}><Icon name="timer" size={29} color={colors.accent} /></View></View>
    <Section title="残り時間">
      <Text testID="timer-clock" accessibilityRole="timer" style={[timerStyles.clock, completed && timerStyles.completed]}>{String(Math.floor(seconds / 60)).padStart(2, '0')}:{String(seconds % 60).padStart(2, '0')}</Text>
      <Text style={[styles.muted, timerStyles.center]}>{completed ? '完了 — リセットしてください' : running ? '実行中' : '停止中'}</Text>
      <View accessibilityRole="progressbar" accessibilityLabel="残り時間の割合" accessibilityValue={{min: 0, max: 100, now: Math.round(progress)}} style={timerStyles.progressTrack}><View style={[timerStyles.progressFill, progressWidth]} /></View>
      <Text style={styles.text}>時間（分）</Text>
      <TextInput accessibilityLabel="時間（分）" keyboardType="number-pad" style={styles.input} value={minutes} editable={!running && !completed} onChangeText={onMinutes} />
      {!valid && <Text style={styles.error}>1〜180の整数を入力してください。</Text>}
      <View style={styles.row}>
        <Button label={running ? '一時停止' : '開始'} variant="primary" icon={!running ? 'arrow' : undefined} disabled={completed || !running && (!valid || !library || busy)} onPress={onToggle} />
        <Button label="リセット" onPress={onReset} />
      </View>
      <Text style={styles.muted}>タブを切り替えてもタイマーは動作します。バックグラウンド中の終了音は保証されません。Prelis の終了時にリセットされます。</Text>
    </Section>
    <Section title="終了音">
      <Text style={styles.muted}>選択中: {selected?.name ?? 'なし'}</Text>
      <Button label={soundOpen ? '音声設定を閉じる' : '音声設定を開く'} onPress={() => setSoundOpen(value => !value)} />
      {!!error && <Text style={styles.error}>{error}</Text>}
      {soundOpen && (!library ? <Button label="再読み込み" onPress={onRetry} /> : <>
        <Text style={styles.muted}>音声を選択</Text>
        <Button label="音声なし" icon={!library.selectedId ? 'check' : undefined} variant="choice" selected={!library.selectedId} disabled={busy || running || completed} onPress={() => onSelectSound(null)} />
        {library.sounds.map(sound => <Button key={sound.id} label={sound.name} icon={library.selectedId === sound.id ? 'check' : undefined} variant="choice" selected={library.selectedId === sound.id} disabled={busy || running || completed} onPress={() => onSelectSound(sound.id)} />)}
        <Button label="音声を追加（MP3 / WAV、10 MB 以下）" disabled={busy || running || completed} onPress={onAddSound} />
        <View style={[styles.row, timerStyles.wrap]}>
          <Button label="試聴" disabled={!selected || busy || running || completed} onPress={() => {if (selected) onPreviewSound(selected.id);}} />
          <Button label="選択中の音声を削除" variant="danger" disabled={!selected || busy || running || completed} onPress={() => {if (selected) onDeleteSound(selected.id);}} />
        </View>
      </>)}
    </Section>
  </ScrollView>;
}

const timerStyles = StyleSheet.create({
  clock: {fontSize: 58, fontWeight: '600', letterSpacing: 1, color: colors.ink, textAlign: 'center'},
  completed: {color: colors.danger},
  progressTrack: {height: 3, borderRadius: 2, backgroundColor: colors.line, overflow: 'hidden'},
  progressFill: {height: 3, borderRadius: 2, backgroundColor: colors.accent},
  center: {textAlign: 'center'},
  wrap: {flexWrap: 'wrap'},
});
