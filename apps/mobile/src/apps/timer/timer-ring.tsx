import React from 'react';
import {StyleSheet, View} from 'react-native';

type Props = {
  size: number;
  progress: number;
  completed: boolean;
  children: React.ReactNode;
};

// Clip two rotating semicircles to draw an arc with native views on both OSes.
export function TimerRing({size, progress, completed, children}: Props) {
  const value = Math.max(0, Math.min(100, progress));
  const angle = value * 3.6;
  const stroke = size / 32;
  const circle = {width: size, height: size, borderRadius: size / 2, borderWidth: stroke};
  const radius = (size - stroke) / 2;
  const radians = angle * Math.PI / 180;
  const cap = {width: stroke, height: stroke, borderRadius: stroke / 2};

  return <View testID="timer-ring" style={{width: size, height: size}}>
    <View
      accessible accessibilityRole="progressbar" accessibilityLabel="残り時間の割合"
      accessibilityValue={{min: 0, max: 100, now: Math.round(value)}}
      pointerEvents="none" style={[StyleSheet.absoluteFill, ringStyles.graphic]}>
      <View style={[ringStyles.circle, circle, {borderColor: completed ? '#d97568' : '#e4f1f8'}]} />
      {!completed && value > 0 && <>
        {value === 100 ? <View style={[ringStyles.circle, circle, ringStyles.progress]} /> : <>
          {[0, 1].map(half => <View key={half} style={[ringStyles.clip, {left: half === 0 ? size / 2 : 0, width: size / 2, height: size}]}>
            <View style={[ringStyles.circle, {left: half === 0 ? -size / 2 : 0, width: size, height: size, transform: [{rotate: `${half === 0 ? Math.min(180, angle) : Math.max(0, angle - 180)}deg`}]}]}>
              <View style={[ringStyles.clip, {left: half === 0 ? 0 : size / 2, width: size / 2, height: size}]}>
                <View style={[ringStyles.circle, circle, ringStyles.progress, {left: half === 0 ? 0 : -size / 2}]} />
              </View>
            </View>
          </View>)}
          <View style={[ringStyles.cap, cap, {left: radius, top: 0}]} />
          <View style={[ringStyles.cap, cap, {left: radius + radius * Math.sin(radians), top: radius - radius * Math.cos(radians)}]} />
        </>}
      </>}
    </View>
    <View style={ringStyles.content}>{children}</View>
  </View>;
}

const ringStyles = StyleSheet.create({
  graphic: {transform: [{scaleX: -1}]},
  circle: {position: 'absolute', top: 0, left: 0},
  progress: {borderColor: '#6ab5da'},
  clip: {position: 'absolute', top: 0, overflow: 'hidden'},
  cap: {position: 'absolute', backgroundColor: '#6ab5da'},
  content: {position: 'absolute', inset: 0, padding: 12, alignItems: 'center', justifyContent: 'center'},
});
