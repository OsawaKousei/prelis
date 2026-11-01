import { useState } from 'react';
import { isTauri } from '@tauri-apps/api/core';
import { openUrl } from '@tauri-apps/plugin-opener';
import { Icon } from '../shared/icon';
import brand from '@prelis/icons/assets/brand.png';
import type { AppDefinition } from './apps';
type Props = {
  readonly apps: readonly AppDefinition[];
  readonly activeId: string | null;
  readonly onSelect: (id: string) => void;
};
const privacyPolicyUrl = 'https://prelis.prj.kupac.co.jp/privacy';

export const Sidebar = ({ apps, activeId, onSelect }: Props) => {
  const [privacyError, setPrivacyError] = useState(false);
  return (
    <aside className="sidebar">
      <div className="brand">
        <img className="brand-mark" src={brand} alt="" />
        <span>
          prelis<span className="brand-dot">.</span>
        </span>
      </div>
      <nav aria-label="アプリ">
        <p className="nav-label">アプリ</p>
        {apps.map((app) => (
          <button
            key={app.id}
            className={`app-link ${activeId === app.id ? 'selected' : ''}`}
            aria-current={activeId === app.id ? 'page' : undefined}
            onClick={() => onSelect(app.id)}
          >
            <Icon name={app.icon} />
            <span>{app.name}</span>
            {activeId === app.id && <span className="active-dot" />}
          </button>
        ))}
      </nav>
      <div className="sidebar-bottom">
        <a
          className="privacy-link"
          href={privacyPolicyUrl}
          target="_blank"
          rel="noopener noreferrer"
          onClick={(event) => {
            if (!isTauri()) return;
            event.preventDefault();
            setPrivacyError(false);
            openUrl(privacyPolicyUrl).catch(() => setPrivacyError(true));
          }}
        >
          プライバシーポリシー
        </a>
        {privacyError && <p className="privacy-error" role="alert">ブラウザーを開けませんでした。リンク先をコピーしてブラウザーで開いてください。</p>}
        <span className="version">v0.1.4</span>
      </div>
    </aside>
  );
};
