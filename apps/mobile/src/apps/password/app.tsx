import React, {useState} from 'react';
import {generatePassword, type CharacterType, type PasswordLength} from '@prelis/core';
import {native} from '../../shared/native';
import {PasswordView} from './password-view';

export function PasswordApp() {
  const [selected, setSelected] = useState<CharacterType[]>(['uppercase', 'lowercase', 'numbers', 'symbols']);
  const [length, setLength] = useState<PasswordLength>(16);
  const [password, setPassword] = useState('');
  const [message, setMessage] = useState('選んだ文字種をそれぞれ1文字以上含めます。');
  const [busy, setBusy] = useState(false);
  const clear = () => {setPassword(''); setMessage('選んだ文字種をそれぞれ1文字以上含めます。');};
  return <PasswordView
    selected={selected} length={length} password={password} message={message} busy={busy}
    onType={type => {
      setSelected(current => current.includes(type) ? current.filter(item => item !== type) : [...current, type]);
      clear();
    }}
    onLength={value => {setLength(value); clear();}}
    onGenerate={async () => {
      setBusy(true);
      try {setPassword(await generatePassword(length, selected, native.randomBytes)); setMessage('');}
      catch {setPassword(''); setMessage('パスワードを生成できませんでした。');}
      finally {setBusy(false);}
    }}
    onCopy={async () => {
      try {await native.copyText(password); setMessage('コピーしました。');}
      catch {setMessage('コピーできませんでした。パスワードを選択してコピーしてください。');}
    }}
  />;
}
