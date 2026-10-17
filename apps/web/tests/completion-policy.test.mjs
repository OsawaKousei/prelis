import test from 'node:test';
import assert from 'node:assert/strict';
import { completionMode } from '../src/apps/timer/completion-policy.ts';

test('表示中に時間になれば終了音を試みる', () => {
  assert.equal(completionMode(1000, 1000, true, false), 'audible');
});

test('非表示中の完了と、背景から戻った後の完了は無音にする', () => {
  assert.equal(completionMode(1000, 1100, false, true), 'silent');
  assert.equal(completionMode(1000, 1100, true, true), 'silent');
});

test('背景から期限前に戻れば計時を続ける', () => {
  assert.equal(completionMode(1000, 900, true, true), 'running');
});
