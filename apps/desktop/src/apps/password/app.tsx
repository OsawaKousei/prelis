import { useRef, useState } from 'react';
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
  const [excludeAmbiguous, setExcludeAmbiguous] = useState(false);
  const [password, setPassword] = useState('');
  const [message, setMessage] = useState('');
  const generation = useRef(0);

  const clearResult = () => {
    generation.current += 1;
    setPassword('');
    setMessage('');
  };

  return (
    <PasswordView
      selectedTypes={selectedTypes}
      length={length}
      excludeAmbiguous={excludeAmbiguous}
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
      onExcludeAmbiguous={(next) => {
        setExcludeAmbiguous(next);
        clearResult();
      }}
      onGenerate={async () => {
        const current = ++generation.current;
        try {
          const result = await generatePassword(length, selectedTypes, excludeAmbiguous);
          if (current !== generation.current) return;
          setPassword(result);
          setMessage('');
        } catch {
          if (current !== generation.current) return;
          setPassword('');
          setMessage('パスワードを生成できませんでした。');
        }
      }}
      onCopy={async () => {
        const current = generation.current;
        try {
          await navigator.clipboard.writeText(password);
          if (current !== generation.current) return;
          setMessage('コピーしました。');
        } catch {
          if (current !== generation.current) return;
          setMessage(
            'コピーできませんでした。パスワードを選択してコピーしてください。',
          );
        }
      }}
    />
  );
};
