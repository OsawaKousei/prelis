import type {IconName} from '../shared/icon';

export type Page = 'home' | 'diary' | 'timer' | 'password';

export const pages: {id: Exclude<Page, 'home'>; label: string; icon: IconName}[] = [
  {id: 'diary', label: 'Diary', icon: 'diary'},
  {id: 'timer', label: 'Timer', icon: 'timer'},
  {id: 'password', label: 'Password', icon: 'password'},
];
