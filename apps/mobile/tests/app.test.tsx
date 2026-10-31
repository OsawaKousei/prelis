import React from 'react';
import {Alert} from 'react-native';
import {act, fireEvent, renderRouter, screen, testRouter} from 'expo-router/testing-library';
import Storage from 'expo-sqlite/kv-store';
import * as Clipboard from 'expo-clipboard';
import {setAudioModeAsync} from 'expo-audio';
import RootLayout from '../src/app/_layout';
import Home from '../src/app/index';
import Diary from '../src/app/diary';
import Timer from '../src/app/timer';
import Password from '../src/app/password';

jest.mock('expo-sqlite/kv-store', () => {
  const values = new Map<string, string>();
  return {__esModule: true, __values: values, default: {
    getItem: jest.fn(async (key: string) => values.get(key) ?? null),
    setItem: jest.fn(async (key: string, value: string) => {values.set(key, value);}),
  }};
});
jest.mock('expo-crypto', () => ({
  getRandomBytesAsync: jest.fn(async (count: number) => new Uint8Array(require('node:crypto').randomBytes(count))),
}));
jest.mock('expo-clipboard', () => ({setStringAsync: jest.fn(async () => true)}));
jest.mock('expo-audio', () => {
  const player = {pause: jest.fn(), replace: jest.fn(), play: jest.fn(), loop: false};
  return {
    __player: player,
    useAudioPlayer: () => player,
    useAudioPlayerStatus: () => ({error: null}),
    setAudioModeAsync: jest.fn(async () => {}),
    setIsAudioActiveAsync: jest.fn(async () => {}),
  };
});
jest.mock('expo-file-system', () => ({
  Paths: {document: 'file:///document'},
  Directory: class {uri = 'file:///document/timer/sounds';},
  File: class {exists = true; uri = 'file:///document/timer/sounds/test.wav';},
}));

const routes = {_layout: RootLayout, index: Home, diary: Diary, timer: Timer, password: Password};

beforeEach(() => {
  jest.clearAllMocks();
  require('expo-sqlite/kv-store').__values.clear();
});

test('keeps a diary draft across tabs and saves through Expo SQLite', async () => {
  await renderRouter(routes);
  await testRouter.navigate('/diary');
  const editor = await screen.findByLabelText('日記の本文');
  await fireEvent.changeText(editor, '今日の日記🙂');
  await testRouter.navigate('/password');
  await testRouter.navigate('/diary');
  expect(screen.getByLabelText('日記の本文')).toHaveDisplayValue('今日の日記🙂');
  await fireEvent.press(screen.getByRole('button', {name: '保存'}));
  expect(Storage.setItem).toHaveBeenCalledWith(expect.stringMatching(/^diary:\d{4}-\d{2}-\d{2}$/), '今日の日記🙂');
});

test('generates with Expo Crypto and copies the result as sensitive content', async () => {
  await renderRouter(routes, {initialUrl: '/password'});
  await fireEvent.press(screen.getByRole('button', {name: 'パスワードを生成'}));
  const result = screen.getByLabelText('生成したパスワード').props.value as string;
  expect(result).toHaveLength(16);
  for (const pattern of [/[A-Z]/, /[a-z]/, /[0-9]/, /[!@#$%^&*_=+?-]/]) expect(result).toMatch(pattern);
  await fireEvent.press(screen.getByRole('button', {name: 'コピー'}));
  expect(Clipboard.setStringAsync).toHaveBeenCalledWith(result, {android: {isSensitive: true}});
});

test('password settings start collapsed and retain choices after closing', async () => {
  await renderRouter(routes, {initialUrl: '/password'});
  expect(screen.queryByRole('button', {name: '8文字'})).toBeNull();
  await fireEvent.press(screen.getByRole('button', {name: '設定を開く'}));
  await fireEvent.press(screen.getByRole('button', {name: '8文字'}));
  await fireEvent.press(screen.getByRole('button', {name: '設定を閉じる'}));
  expect(screen.queryByRole('button', {name: '8文字'})).toBeNull();
  await fireEvent.press(screen.getByRole('button', {name: 'パスワードを生成'}));
  expect(screen.getByLabelText('生成したパスワード').props.value).toHaveLength(8);
});

test('diary calendar starts collapsed and expanding it preserves the draft', async () => {
  await renderRouter(routes, {initialUrl: '/diary'});
  await fireEvent.changeText(await screen.findByLabelText('日記の本文'), 'カレンダー操作中の下書き');
  expect(screen.queryByRole('button', {name: '前の月'})).toBeNull();
  await fireEvent.press(screen.getByRole('button', {name: 'カレンダーを開く'}));
  expect(screen.getByRole('button', {name: '前の月'})).toBeVisible();
  await fireEvent.press(screen.getByRole('button', {name: 'カレンダーを閉じる'}));
  expect(screen.queryByRole('button', {name: '前の月'})).toBeNull();
  expect(screen.getByLabelText('日記の本文')).toHaveDisplayValue('カレンダー操作中の下書き');
});

test('does not carry a discarded diary draft into a date that fails to load', async () => {
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  try {
    await renderRouter(routes, {initialUrl: '/diary'});
    await fireEvent.changeText(await screen.findByLabelText('日記の本文'), '破棄する下書き');
    await fireEvent.press(screen.getByRole('button', {name: '翌日'}));
    jest.mocked(Storage.getItem).mockRejectedValueOnce(new Error('disk unavailable'));
    const discard = alert.mock.calls[0][2]?.find(button => button.text === '変更を破棄');
    expect(discard).toBeDefined();
    await act(async () => {discard?.onPress?.();});
    expect(await screen.findByRole('button', {name: 'もう一度読み込む'})).toBeEnabled();
    expect(screen.queryByLabelText('日記の本文')).toBeNull();
    expect(Storage.setItem).not.toHaveBeenCalled();
  } finally {alert.mockRestore();}
});

test('keeps a timer across routes, loops its sound at completion and stops it on reset', async () => {
  jest.useFakeTimers();
  try {
    const sound = {id: '12345678-1234-4234-8234-123456789abc', name: 'test.wav', mimeType: 'audio/wav'};
    require('expo-sqlite/kv-store').__values.set('timer:sounds', JSON.stringify({sounds: [sound], selectedId: sound.id}));
    await renderRouter(routes, {initialUrl: '/timer'});
    await fireEvent.changeText(screen.getByLabelText('時間（分）'), '1');
    await fireEvent.press(screen.getByRole('button', {name: '開始'}));
    await testRouter.navigate('/password');
    await act(async () => {jest.advanceTimersByTime(30_000);});
    await testRouter.navigate('/timer');
    expect(screen.getByTestId('timer-clock')).toHaveTextContent('00:30');
    await act(async () => {jest.advanceTimersByTime(30_000);});
    expect(screen.getByTestId('timer-clock')).toHaveTextContent('00:00');
    const player = require('expo-audio').__player;
    expect(player.loop).toBe(true);
    expect(player.play).toHaveBeenCalledTimes(1);
    await fireEvent.press(screen.getByRole('button', {name: 'リセット'}));
    expect(player.replace).toHaveBeenLastCalledWith(null);
    expect(screen.getByTestId('timer-clock')).toHaveTextContent('01:00');
  } finally {jest.useRealTimers();}
});

test('reset cancels a preview whose native audio setup is still pending', async () => {
  const sound = {id: '12345678-1234-4234-8234-123456789abc', name: 'test.wav', mimeType: 'audio/wav'};
  require('expo-sqlite/kv-store').__values.set('timer:sounds', JSON.stringify({sounds: [sound], selectedId: sound.id}));
  let finish!: () => void;
  const pending = new Promise<void>(resolve => {finish = resolve;});
  jest.mocked(setAudioModeAsync).mockImplementationOnce(() => pending);
  await renderRouter(routes, {initialUrl: '/timer'});
  await fireEvent.press(screen.getByRole('button', {name: '音声設定を開く'}));
  await fireEvent.press(screen.getByRole('button', {name: '試聴'}));
  await fireEvent.press(screen.getByRole('button', {name: 'リセット'}));
  await act(async () => {finish();});
  const player = require('expo-audio').__player;
  expect(player.play).not.toHaveBeenCalled();
  expect(player.replace).toHaveBeenLastCalledWith(null);
});
