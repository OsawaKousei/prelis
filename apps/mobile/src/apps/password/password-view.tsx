import React from 'react';
import {ScrollView, StyleSheet, Text, TextInput, View} from 'react-native';
import type {CharacterType, PasswordLength} from '@prelis/core';
import {Button, colors, Section, styles} from '../../shared/ui';
import {Icon} from '../../shared/icon';

type Props = {
  selected: CharacterType[];
  length: PasswordLength;
  password: string;
  message: string;
  busy: boolean;
  onType: (type: CharacterType) => void;
  onLength: (length: PasswordLength) => void;
  onGenerate: () => Promise<void>;
  onCopy: () => Promise<void>;
};

const types: {key: CharacterType; label: string}[] = [
  {key: 'uppercase', label: '大文字 A–Z'}, {key: 'lowercase', label: '小文字 a–z'},
  {key: 'numbers', label: '数字 0–9'}, {key: 'symbols', label: '記号 ! @ # …'},
];
const lengths: PasswordLength[] = [4, 8, 12, 16];

export function PasswordView({selected, length, password, message, busy, onType, onLength, onGenerate, onCopy}: Props) {
  return <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
    <View style={styles.pageIntro}><Text style={styles.heading}>パスワード生成</Text><View style={styles.emblem}><Icon name="password" size={29} color={colors.accent} /></View></View>
    <Section title="使用する文字"><View style={passwordStyles.options}>{types.map(type => <View key={type.key} style={passwordStyles.optionItem}><Button label={type.label} icon={selected.includes(type.key) ? 'check' : undefined} variant="choice" selected={selected.includes(type.key)} disabled={busy} onPress={() => onType(type.key)} /></View>)}</View></Section>
    <Section title="文字数"><View style={passwordStyles.lengths}>{lengths.map(value => <View key={value} style={passwordStyles.lengthItem}><Button label={`${value}文字`} icon={length === value ? 'check' : undefined} variant="choice" selected={length === value} disabled={busy} onPress={() => onLength(value)} /></View>)}</View></Section>
    {length <= 8 && <Text style={styles.error}>{length}文字のパスワードは推測されやすいため、利用先が許すなら16文字を選んでください。</Text>}
    {selected.length === 0 && <Text style={styles.error}>文字種を1つ以上選択してください。</Text>}
    <Button label={busy ? '生成中…' : 'パスワードを生成'} disabled={selected.length === 0 || busy} variant="primary" onPress={onGenerate} />
    <Section title="生成したパスワード">
      <TextInput accessibilityLabel="生成したパスワード" style={styles.input} value={password} placeholder="未生成" editable={false} selectTextOnFocus />
      <Button label="コピー" disabled={!password} onPress={onCopy} />
      <Text style={styles.muted}>{message}</Text>
    </Section>
  </ScrollView>;
}

const passwordStyles = StyleSheet.create({
  options: {flexDirection: 'row', flexWrap: 'wrap', gap: 10},
  optionItem: {width: '48%'},
  lengths: {flexDirection: 'row', flexWrap: 'wrap', gap: 8},
  lengthItem: {width: '22%'},
});
