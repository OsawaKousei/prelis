import type { ComponentType } from 'react';
import { DiaryApp } from '../apps/diary/app';
import { TimerApp } from '../apps/timer/app';
import { PasswordApp } from '../apps/password/app';
export type AppDefinition = {
  readonly id: string;
  readonly name: string;
  readonly icon: 'diary' | 'timer' | 'password';
  readonly component: ComponentType;
  readonly keepMounted?: boolean;
};
export const apps: readonly AppDefinition[] = [
  {
    id: 'diary',
    name: 'Diary',
    icon: 'diary',
    component: DiaryApp,
  },
  {
    id: 'timer',
    name: 'Timer',
    icon: 'timer',
    component: TimerApp,
    keepMounted: true,
  },
  {
    id: 'password',
    name: 'Password',
    icon: 'password',
    component: PasswordApp,
  },
];
