/** @format */
import React from 'react';
import ReactTestRenderer from 'react-test-renderer';
import {Button} from '../src/ui';
import App from '../App';

jest.mock('react-native-safe-area-context', () => require('react-native-safe-area-context/jest/mock').default);
jest.mock('../src/native', () => ({
  native: {
    readDiary: jest.fn(async () => ''), saveDiary: jest.fn(async () => true),
    loadSounds: jest.fn(async () => '{"version":1,"sounds":[],"selectedId":null}'),
    randomBytes: jest.fn(async (count: number) => [...require('crypto').randomBytes(count)]),
    copyText: jest.fn(async () => true), stopSound: jest.fn(async () => true),
  },
  parseSounds: (value: string) => JSON.parse(value),
}));

const press = (root: ReactTestRenderer.ReactTestInstance, label: string) => {
  root.findAllByType(Button).find(item => item.props.label === label)!.props.onPress();
};

test('opens Diary, edits and saves an entry', async () => {
  let renderer: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(async () => {renderer = ReactTestRenderer.create(<App />);});
  await ReactTestRenderer.act(async () => {press(renderer!.root, 'Diary');});
  const editor = renderer!.root.findByProps({testID: 'diary-content'});
  await ReactTestRenderer.act(async () => {editor.props.onChangeText('今日の日記');});
  await ReactTestRenderer.act(async () => {press(renderer!.root, '保存');});
  const {native} = require('../src/native');
  expect(native.saveDiary).toHaveBeenCalledWith(expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/), '今日の日記');
  await ReactTestRenderer.act(async () => {renderer!.unmount();});
});

test('generates a password containing every selected character type', async () => {
  let renderer: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(async () => {renderer = ReactTestRenderer.create(<App />);});
  await ReactTestRenderer.act(async () => {press(renderer!.root, 'Password');});
  await ReactTestRenderer.act(async () => {press(renderer!.root, 'パスワードを生成');});
  const value = renderer!.root.findByProps({accessibilityLabel: '生成したパスワード'}).props.value as string;
  expect(value).toHaveLength(16);
  expect(value).toMatch(/[A-Z]/);
  expect(value).toMatch(/[a-z]/);
  expect(value).toMatch(/[0-9]/);
  expect(value).toMatch(/[!@#$%^&*_=+?-]/);
  await ReactTestRenderer.act(async () => {renderer!.unmount();});
});

test('timer reaches completion and starts its selected sound', async () => {
  jest.useFakeTimers();
  const {native} = require('../src/native');
  native.loadSounds.mockResolvedValueOnce(JSON.stringify({version: 1, sounds: [{id: 'sound-1', name: 'test.wav', mimeType: 'audio/wav'}], selectedId: 'sound-1'}));
  native.playSound = jest.fn(async () => true);
  let renderer: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(async () => {renderer = ReactTestRenderer.create(<App />);});
  await ReactTestRenderer.act(async () => {press(renderer!.root, 'Timer');});
  const minutes = renderer!.root.findByProps({accessibilityLabel: '時間（分）'});
  await ReactTestRenderer.act(async () => {minutes.props.onChangeText('1');});
  await ReactTestRenderer.act(async () => {press(renderer!.root, '開始');});
  await ReactTestRenderer.act(async () => {jest.advanceTimersByTime(60_000);});
  expect(renderer!.root.findByProps({testID: 'timer-clock'}).props.children.join('')).toBe('00:00');
  expect(native.playSound).toHaveBeenCalledWith('sound-1', true);
  await ReactTestRenderer.act(async () => {renderer!.unmount();});
  jest.useRealTimers();
});
