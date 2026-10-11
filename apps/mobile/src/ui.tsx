import React from 'react';
import {Pressable, StyleSheet, Text, View} from 'react-native';

import {colors} from './theme';
import {Icon, type IconName} from './icon';
export {colors} from './theme';

export const styles = StyleSheet.create({
  screen: {flex: 1, backgroundColor: colors.background},
  content: {paddingHorizontal: 24, paddingTop: 30, paddingBottom: 48, gap: 28},
  pageIntro: {flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between'},
  emblem: {width: 52, height: 52, alignItems: 'center', justifyContent: 'center', borderRadius: 26, backgroundColor: colors.accentSoft},
  heading: {fontSize: 32, lineHeight: 40, fontWeight: '600', letterSpacing: 0.2, color: colors.ink},
  subheading: {fontSize: 20, lineHeight: 28, fontWeight: '600', color: colors.ink},
  text: {fontSize: 16, lineHeight: 24, color: colors.ink},
  muted: {fontSize: 14, lineHeight: 21, color: colors.muted},
  error: {fontSize: 14, lineHeight: 21, color: colors.danger},
  row: {flexDirection: 'row', alignItems: 'center', gap: 10},
  section: {paddingTop: 22, borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.line, gap: 14},
  input: {minHeight: 52, borderWidth: 1, borderColor: colors.line, borderRadius: 9, paddingHorizontal: 14, paddingVertical: 10, color: colors.ink, fontSize: 16, backgroundColor: colors.surface},
});

type ButtonVariant = 'secondary' | 'primary' | 'choice' | 'tab' | 'launch' | 'danger';
type ButtonProps = {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  selected?: boolean;
  testID?: string;
  variant?: ButtonVariant;
  icon?: IconName;
};

export function Button({label, onPress, disabled, selected, testID, variant = 'secondary', icon}: ButtonProps) {
  const iconColor = variant === 'danger' ? colors.danger : selected || variant === 'primary' || variant === 'launch' ? colors.accent : variant === 'tab' ? colors.muted : colors.ink;
  return <Pressable
    testID={testID}
    accessibilityRole="button"
    accessibilityLabel={label}
    accessibilityState={{disabled: !!disabled, selected: !!selected}}
    disabled={disabled}
    onPress={onPress}
    style={({pressed}) => [
      buttonStyles.base,
      variant === 'primary' && buttonStyles.primary,
      variant === 'choice' && buttonStyles.choice,
      variant === 'tab' && buttonStyles.tab,
      variant === 'launch' && buttonStyles.launch,
      variant === 'danger' && buttonStyles.danger,
      selected && variant === 'choice' && buttonStyles.choiceSelected,
      selected && variant === 'tab' && buttonStyles.tabSelected,
      disabled && buttonStyles.disabled,
      pressed && buttonStyles.pressed,
    ]}>
    <View style={[buttonStyles.content, variant === 'tab' && buttonStyles.tabContent]}>
      {variant === 'choice' ? <View style={buttonStyles.choiceIcon}>{icon && <Icon name={icon} size={18} color={iconColor} />}</View> : icon && <Icon name={icon} size={variant === 'launch' ? 24 : variant === 'tab' ? 19 : 18} color={iconColor} />}
      <Text style={[
        buttonStyles.label,
        variant === 'primary' && buttonStyles.primaryLabel,
        variant === 'tab' && buttonStyles.tabLabel,
        variant === 'launch' && buttonStyles.launchLabel,
        variant === 'danger' && buttonStyles.dangerLabel,
        selected && (variant === 'choice' || variant === 'tab') && buttonStyles.selectedLabel,
      ]}>{label}</Text>
    </View>
    {variant === 'launch' && <Icon name="arrow" size={19} color={colors.accent} />}
  </Pressable>;
}

const buttonStyles = StyleSheet.create({
  content: {flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8},
  choiceIcon: {width: 18, height: 18},
  tabContent: {flexDirection: 'column', gap: 2},
  base: {minHeight: 48, minWidth: 44, justifyContent: 'center', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 10, borderRadius: 9, backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.line},
  primary: {backgroundColor: colors.accentSoft, borderColor: colors.accentLine, minHeight: 52},
  choice: {backgroundColor: colors.surface, borderColor: colors.line},
  choiceSelected: {backgroundColor: colors.accentSoft, borderColor: colors.accentLine},
  tab: {minHeight: 52, minWidth: 0, paddingHorizontal: 8, paddingVertical: 8, borderWidth: 0, borderBottomWidth: 2, borderBottomColor: 'transparent', borderRadius: 0, backgroundColor: 'transparent'},
  tabSelected: {borderBottomColor: colors.accent},
  launch: {minHeight: 76, flexDirection: 'row', justifyContent: 'space-between', borderWidth: 0, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: colors.line, borderRadius: 0, backgroundColor: 'transparent', paddingHorizontal: 2},
  danger: {borderColor: '#E9C7C5', backgroundColor: '#FFF8F7'},
  disabled: {opacity: 0.46},
  pressed: {opacity: 0.68},
  label: {fontSize: 15, lineHeight: 21, fontWeight: '600', color: colors.ink, textAlign: 'center'},
  primaryLabel: {fontSize: 16, color: '#075A76'},
  tabLabel: {fontSize: 13, color: colors.muted},
  launchLabel: {fontSize: 20, fontWeight: '600'},
  dangerLabel: {color: colors.danger},
  selectedLabel: {color: colors.accent},
});

export function Section({title, children}: {title: string; children: React.ReactNode}) {
  return <View style={styles.section}><Text style={styles.subheading}>{title}</Text>{children}</View>;
}
