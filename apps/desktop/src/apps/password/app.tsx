import { useState } from 'react';
import { generatePassword } from './password';
import type { CharacterType, PasswordLength } from './password';
import { PasswordView } from './password-view';
import './password.css';

export const PasswordApp = () => {
  const [selectedTypes, setSelectedTypes] = useState<readonly CharacterType[]>([
    'uppercase',
    'lowercase',
    'numbers',
    'symbols',
  ]);
  const [length, setLength] = useState<PasswordLength>(16);
  const [password, setPassword] = useState('');
  const [message, setMessage] = useState('');

  const clearResult = () => {
    setPassword('');
    setMessage('');
  };

  return (
    <PasswordView
      selectedTypes={selectedTypes}
      length={length}
      password={password}
      message={message}
      onToggleType={(type) => {
        setSelectedTypes((current) =>
          current.includes(type)
            ? current.filter((item) => item !== type)
            : [...current, type],
        );
        clearResult();
      }}
      onLength={(next) => {
        setLength(next);
        clearResult();
      }}
      onGenerate={() => {
        try {
          setPassword(generatePassword(length, selectedTypes));
          setMessage('');
        } catch {
          setPassword('');
          setMessage('パスワードを生成できませんでした。');
        }
      }}
      onCopy={async () => {
        try {
          await navigator.clipboard.writeText(password);
          setMessage('コピーしました。');
        } catch {
          setMessage(
            'コピーできませんでした。パスワードを選択してコピーしてください。',
          );
        }
      }}
    />
  );
};
