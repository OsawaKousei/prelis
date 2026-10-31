import React from 'react';
import {Image} from 'react-native';
import type {IconName} from '@prelis/icons';
import {colors} from './theme';

export type {IconName} from '@prelis/icons';

const images: Record<IconName, number> = {
  arrow: require('@prelis/icons/assets/arrow.png'),
  check: require('@prelis/icons/assets/check.png'),
  close: require('@prelis/icons/assets/close.png'),
  diary: require('@prelis/icons/assets/diary.png'),
  home: require('@prelis/icons/assets/home.png'),
  left: require('@prelis/icons/assets/left.png'),
  password: require('@prelis/icons/assets/password.png'),
  right: require('@prelis/icons/assets/right.png'),
  save: require('@prelis/icons/assets/save.png'),
  timer: require('@prelis/icons/assets/timer.png'),
};

export function Icon({name, size = 20, color = colors.ink}: {name: IconName; size?: number; color?: string}) {
  return <Image source={images[name]} accessible={false} resizeMode="contain" style={{width: size, height: size, tintColor: color}} />;
}
