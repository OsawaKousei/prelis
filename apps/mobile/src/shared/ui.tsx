import React from 'react';
import {Platform, Pressable, ScrollView, StyleSheet, Text, View, type StyleProp, type ViewStyle} from 'react-native';

import {colors} from './theme';
import {Icon, type IconName} from './icon';
export {colors} from './theme';

export const styles = StyleSheet.create({
  screen: {flex: 1, backgroundColor: colors.background},
  content: {flexGrow: 1, paddingHorizontal: 16, paddingVertical: 8, gap: 10},
  pageIntro: {flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between'},
  emblem: {width: 32, height: 32, alignItems: 'center', justifyContent: 'center', borderRadius: 16, backgroundColor: colors.accentSoft},
  heading: {flexShrink: 1, fontSize: 26, lineHeight: 32, fontWeight: '600', letterSpacing: 0.2, color: colors.ink},
  subheading: {fontSize: 18, lineHeight: 24, fontWeight: '600', color: colors.ink},
  text: {fontSize: 16, lineHeight: 24, color: colors.ink},
  muted: {fontSize: 14, lineHeight: 20, color: colors.muted},
  caption: {fontSize: 12, lineHeight: 18, color: colors.muted},
  error: {fontSize: 14, lineHeight: 21, color: colors.danger},
  row: {flexDirection: 'row', alignItems: 'center', gap: 10},
  section: {paddingTop: 10, borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.line, gap: 8},
  input: {minHeight: Platform.OS === 'android' ? 48 : 44, borderWidth: 1, borderColor: colors.line, borderRadius: 9, paddingHorizontal: 12, paddingVertical: 8, color: colors.ink, fontSize: 16, backgroundColor: colors.surface},
});

export function Page({id, children, contentStyle}: {id: string; children: React.ReactNode; contentStyle?: StyleProp<ViewStyle>}) {
  return <ScrollView testID={`page-${id}`} style={styles.screen} contentContainerStyle={[styles.content, contentStyle]} bounces={false} alwaysBounceVertical={false} automaticallyAdjustKeyboardInsets keyboardShouldPersistTaps="handled">
    {children}
  </ScrollView>;
}

type ButtonVariant = 'secondary' | 'primary' | 'choice' | 'tab' | 'launch' | 'danger';
type ButtonProps = {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  selected?: boolean;
  testID?: string;
  variant?: ButtonVariant;
  icon?: IconName;
  accessibilityLabel?: string;
  expanded?: boolean;
};

export function Button({label, onPress, disabled, selected, testID, variant = 'secondary', icon, accessibilityLabel, expanded}: ButtonProps) {
  const iconColor = variant === 'danger' ? colors.danger : selected || variant === 'primary' || variant === 'launch' ? colors.accent : variant === 'tab' ? colors.muted : colors.ink;
  return <Pressable
    testID={testID}
    accessibilityRole="button"
    accessibilityLabel={accessibilityLabel ?? label}
    accessibilityState={{disabled: !!disabled, selected: !!selected, ...(expanded === undefined ? {} : {expanded})}}
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
  base: {minHeight: Platform.OS === 'android' ? 48 : 44, minWidth: 44, justifyContent: 'center', alignItems: 'center', paddingHorizontal: 12, paddingVertical: 8, borderRadius: 9, backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.line},
  primary: {backgroundColor: colors.accentSoft, borderColor: colors.accentLine},
  choice: {backgroundColor: colors.surface, borderColor: colors.line},
  choiceSelected: {backgroundColor: colors.accentSoft, borderColor: colors.accentLine},
  tab: {minHeight: 52, minWidth: 0, paddingHorizontal: 8, paddingVertical: 8, borderWidth: 0, borderBottomWidth: 2, borderBottomColor: 'transparent', borderRadius: 0, backgroundColor: 'transparent'},
  tabSelected: {borderBottomColor: colors.accent},
  launch: {minHeight: 64, flexDirection: 'row', justifyContent: 'space-between', borderWidth: 0, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: colors.line, borderRadius: 0, backgroundColor: 'transparent', paddingHorizontal: 2},
  danger: {borderColor: '#E9C7C5', backgroundColor: '#FFF8F7'},
  disabled: {opacity: 0.46},
  pressed: {opacity: 0.68},
  label: {flexShrink: 1, fontSize: 15, lineHeight: 21, fontWeight: '600', color: colors.ink, textAlign: 'center'},
  primaryLabel: {fontSize: 16, color: '#075A76'},
  tabLabel: {fontSize: 13, color: colors.muted},
  launchLabel: {fontSize: 20, fontWeight: '600'},
  dangerLabel: {color: colors.danger},
  selectedLabel: {color: colors.accent},
});

export function Section({title, children}: {title: string; children: React.ReactNode}) {
  return <View style={styles.section}><Text style={styles.subheading}>{title}</Text>{children}</View>;
}
