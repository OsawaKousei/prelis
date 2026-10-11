import React, {useCallback, useEffect, useState} from 'react';
import {ScrollView, StyleSheet, Text, TextInput, View} from 'react-native';
import {native, parseSounds, type SoundLibrary} from './native';
import {Button, Section, styles} from './ui';

export function Timer() {
  const [minutes, setMinutes] = useState('25');
  const duration = Number(minutes);
  const valid = /^\d+$/.test(minutes) && Number.isInteger(duration) && duration >= 1 && duration <= 180;
  const [remaining, setRemaining] = useState(25 * 60 * 1000);
  const [deadline, setDeadline] = useState<number | null>(null);
  const [library, setLibrary] = useState<SoundLibrary | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [retry, setRetry] = useState(0);
  const completed = remaining === 0;
  const selected = library?.sounds.find(sound => sound.id === library.selectedId);
  useEffect(() => {
    let active = true;
    native.loadSounds().then(value => {if (active) {setLibrary(parseSounds(value)); setError('');}})
      .catch(() => {if (active) setError('保存済みの音声を読み込めませんでした。');});
    return () => {active = false;};
  }, [retry]);
  const playCompletion = useCallback(() => {
    if (library?.selectedId) native.playSound(library.selectedId, true).catch(() => setError('終了音を再生できませんでした。'));
  }, [library]);
  useEffect(() => {
    if (deadline === null) return;
    const id = setInterval(() => {
      const next = Math.max(0, deadline - Date.now());
      setRemaining(next);
      if (next === 0) {
        clearInterval(id);
        setDeadline(null);
        playCompletion();
      }
    }, 100);
    return () => clearInterval(id);
  }, [deadline, playCompletion]);
  const changeSounds = async (action: () => Promise<string | null>) => {
    if (busy || !library || deadline !== null || completed) return;
    setBusy(true); setError('');
    try {const value = await action(); if (value) setLibrary(parseSounds(value));}
    catch (reason) {setError(reason instanceof Error ? reason.message : '音声を変更できませんでした。');}
    finally {setBusy(false);}
  };
  const seconds = Math.ceil(remaining / 1000);
  return <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
    <Text style={styles.heading}>Timer</Text>
    <Section title="残り時間">
      <Text testID="timer-clock" accessibilityRole="timer" style={[timerStyles.clock, completed && timerStyles.completed]}>{String(Math.floor(seconds / 60)).padStart(2, '0')}:{String(seconds % 60).padStart(2, '0')}</Text>
      <Text style={[styles.muted, timerStyles.center]}>{completed ? '完了 — リセットしてください' : deadline !== null ? '実行中' : '停止中'}</Text>
      <Text style={styles.text}>時間（分）</Text>
      <TextInput accessibilityLabel="時間（分）" keyboardType="number-pad" style={styles.input} value={minutes} editable={deadline === null && !completed} onChangeText={value => {
        setMinutes(value);
        const next = Number(value);
        if (/^\d+$/.test(value) && Number.isInteger(next) && next >= 1 && next <= 180) setRemaining(next * 60 * 1000);
      }} />
      {!valid && <Text style={styles.error}>1〜180の整数を入力してください。</Text>}
      <View style={styles.row}>
        <Button label={deadline !== null ? '一時停止' : '開始'} selected disabled={completed || deadline === null && (!valid || !library || busy)} onPress={() => {
          if (deadline !== null) {
            const next = Math.max(0, deadline - Date.now());
            setRemaining(next); setDeadline(null);
            if (next === 0) playCompletion();
          } else setDeadline(Date.now() + remaining);
        }} />
        <Button label="リセット" onPress={() => {
          native.stopSound().catch(() => setError('終了音を停止できませんでした。'));
          setDeadline(null);
          if (!valid) setMinutes('25');
          setRemaining((valid ? duration : 25) * 60 * 1000);
        }} />
      </View>
      <Text style={styles.muted}>アプリを切り替えてもタイマーは動作します。Prelis の終了時にリセットされます。</Text>
    </Section>
    <Section title={`終了音: ${selected?.name ?? 'なし'}`}>
      {!library ? <Button label="再読み込み" onPress={() => setRetry(value => value + 1)} /> : <>
        <Text style={styles.muted}>音声を選択</Text>
        <Button label="音声なし" selected={!library.selectedId} disabled={busy || deadline !== null || completed} onPress={() => changeSounds(() => native.selectSound(null))} />
        {library.sounds.map(sound => <Button key={sound.id} label={sound.name} selected={library.selectedId === sound.id} disabled={busy || deadline !== null || completed} onPress={() => changeSounds(() => native.selectSound(sound.id))} />)}
        <Button label="音声を追加（MP3 / WAV、10 MB 以下）" disabled={busy || deadline !== null || completed} onPress={() => changeSounds(native.pickSound)} />
        <View style={[styles.row, timerStyles.wrap]}>
          <Button label="試聴" disabled={!selected || busy || deadline !== null || completed} onPress={() => {if (selected) native.playSound(selected.id, false).catch(() => setError('音声を再生できませんでした。'));}} />
          <Button label="選択中の音声を削除" disabled={!selected || busy || deadline !== null || completed} onPress={() => {if (selected) changeSounds(() => native.deleteSound(selected.id));}} />
        </View>
      </>}
      {!!error && <Text style={styles.error}>{error}</Text>}
    </Section>
  </ScrollView>;
}

const timerStyles = StyleSheet.create({
  clock: {fontSize: 58, fontWeight: '700', color: '#3557c4', textAlign: 'center'},
  completed: {color: '#b42318'},
  center: {textAlign: 'center'},
  wrap: {flexWrap: 'wrap'},
});
