import type { CharacterType, PasswordLength } from './password';
import { Icon } from '../../shared/icon';

const types: ReadonlyArray<{
  key: CharacterType;
  label: string;
  example: string;
}> = [
  { key: 'uppercase', label: '大文字', example: 'A–Z' },
  { key: 'lowercase', label: '小文字', example: 'a–z' },
  { key: 'numbers', label: '数字', example: '0–9' },
  { key: 'symbols', label: '記号', example: '! @ # …' },
];

const lengths: readonly PasswordLength[] = [4, 8, 12, 16];

type Props = {
  readonly selectedTypes: readonly CharacterType[];
  readonly length: PasswordLength;
  readonly excludeAmbiguous: boolean;
  readonly password: string;
  readonly message: string;
  readonly onToggleType: (type: CharacterType) => void;
  readonly onLength: (length: PasswordLength) => void;
  readonly onExcludeAmbiguous: (exclude: boolean) => void;
  readonly onGenerate: () => void;
  readonly onCopy: () => void;
};

export const PasswordView = ({
  selectedTypes,
  length,
  excludeAmbiguous,
  password,
  message,
  onToggleType,
  onLength,
  onExcludeAmbiguous,
  onGenerate,
  onCopy,
}: Props) => (
  <div className="password-workspace">
    <header className="password-intro">
      <div>
        <h1>パスワード生成</h1>
        <p>条件を選んで、新しいパスワードを作成します。</p>
      </div>
      <span className="app-emblem" aria-hidden="true">
        <Icon name="password" size={32} />
      </span>
    </header>

    <div className="password-layout">
      <section
        className="password-panel"
        aria-labelledby="password-settings-title"
      >
        <h2 id="password-settings-title">生成条件</h2>
        <div className="password-options-grid">
          <fieldset className="password-options">
            <legend>使用する文字</legend>
            <div className="password-type-grid">
              {types.map(({ key, label, example }) => (
                <label className="password-type" key={key}>
                  <input
                    type="checkbox"
                    checked={selectedTypes.includes(key)}
                    onChange={() => onToggleType(key)}
                  />
                  <span>{label}</span>
                  <small>{example}</small>
                </label>
              ))}
            </div>
          </fieldset>

          <fieldset className="password-options">
            <legend>文字数</legend>
            <div className="password-lengths">
              {lengths.map((option) => (
                <label key={option}>
                  <input
                    type="radio"
                    name="password-length"
                    checked={length === option}
                    onChange={() => onLength(option)}
                  />
                  <span>{option}文字</span>
                </label>
              ))}
            </div>
          </fieldset>
        </div>

        <div className="password-exclusion">
          <label>
            <input
              type="checkbox"
              checked={excludeAmbiguous}
              onChange={(event) => onExcludeAmbiguous(event.target.checked)}
              aria-describedby="password-exclusion-description"
            />
            <span>間違えやすい文字を除く</span>
          </label>
          <p id="password-exclusion-description" className="password-hint">
            英大文字の I・O、英小文字の l、数字の 0・1 を除外します。
          </p>
        </div>

        {length <= 8 && (
          <p className="password-warning">
            {length}
            文字のパスワードは推測されやすいため、利用先が許すなら16文字を選んでください。
          </p>
        )}

        <div className="password-action-row">
          <button
            className="primary-button password-generate"
            type="button"
            disabled={selectedTypes.length === 0}
            onClick={onGenerate}
          >
            パスワードを生成
          </button>
          {selectedTypes.length === 0 && (
            <p className="password-hint">文字種を1つ以上選択してください。</p>
          )}
        </div>
      </section>

      <section
        className="password-result"
        aria-labelledby="password-result-title"
      >
        <h2 id="password-result-title">生成したパスワード</h2>
        <div className="password-result-row">
          <input
            type="text"
            aria-label="生成したパスワード"
            value={password}
            placeholder="未生成"
            readOnly
            spellCheck={false}
            autoComplete="off"
          />
          <button type="button" onClick={onCopy} disabled={!password}>
            コピー
          </button>
        </div>
        <p className="password-hint" role="status">
          {message || '選んだ文字種をそれぞれ1文字以上含めます。'}
        </p>
      </section>
    </div>
  </div>
);
