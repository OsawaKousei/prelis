import React from 'react';
import {Pressable, StyleSheet, Text, View} from 'react-native';

export const colors = {background: '#f7f8fa', ink: '#1d2939', muted: '#667085', line: '#d0d5dd', accent: '#3557c4', pale: '#e8edff', danger: '#b42318'};
export const styles = StyleSheet.create({
  screen: {flex: 1, backgroundColor: colors.background},
  content: {padding: 20, gap: 18, paddingBottom: 40},
  heading: {fontSize: 30, fontWeight: '700', color: colors.ink},
  subheading: {fontSize: 18, fontWeight: '700', color: colors.ink},
  text: {fontSize: 16, color: colors.ink},
  muted: {fontSize: 14, color: colors.muted},
  error: {fontSize: 14, color: colors.danger},
  row: {flexDirection: 'row', alignItems: 'center', gap: 10},
  card: {backgroundColor: '#fff', borderRadius: 16, padding: 16, gap: 12, borderWidth: 1, borderColor: '#eaecf0'},
  input: {borderWidth: 1, borderColor: colors.line, borderRadius: 10, padding: 12, color: colors.ink, fontSize: 16, backgroundColor: '#fff'},
});

export function Button({label, onPress, disabled, selected, testID}: {label: string; onPress: () => void; disabled?: boolean; selected?: boolean; testID?: string}) {
  return <Pressable testID={testID} accessibilityRole="button" accessibilityLabel={label} accessibilityState={{disabled: !!disabled, selected: !!selected}} disabled={disabled} onPress={onPress} style={[buttonStyles.button, selected && buttonStyles.selected, disabled && buttonStyles.disabled]}>
    <Text style={[buttonStyles.label, selected && buttonStyles.selectedLabel]}>{label}</Text>
  </Pressable>;
}
const buttonStyles = StyleSheet.create({
  button: {minHeight: 44, minWidth: 44, justifyContent: 'center', alignItems: 'center', paddingHorizontal: 14, borderRadius: 10, backgroundColor: '#fff', borderWidth: 1, borderColor: colors.line},
  selected: {backgroundColor: colors.accent, borderColor: colors.accent},
  disabled: {opacity: 0.45},
  label: {fontSize: 15, fontWeight: '600', color: colors.ink},
  selectedLabel: {color: '#fff'},
});
export function Section({title, children}: {title: string; children: React.ReactNode}) {
  return <View style={styles.card}><Text style={styles.subheading}>{title}</Text>{children}</View>;
}
