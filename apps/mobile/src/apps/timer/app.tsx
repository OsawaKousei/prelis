import React from 'react';
import {useTimer} from './timer-provider';
import {TimerView} from './timer-view';

export function TimerApp() {
  const timer = useTimer();
  return <TimerView {...timer} />;
}
