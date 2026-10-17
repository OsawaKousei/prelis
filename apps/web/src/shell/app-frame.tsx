import type { ReactNode } from 'react';
import { Icon } from '../shared/icon';
export const AppFrame = ({
  name,
  children,
  onClose,
  hidden,
}: {
  readonly name: string;
  readonly children: ReactNode;
  readonly onClose: () => void;
  readonly hidden?: boolean;
}) => (
  <main className="app-frame" hidden={hidden}>
    <header className="frame-header">
      <span className="frame-breadcrumb">
        アプリ <span>/</span> <strong>{name}</strong>
      </span>
      <button className="text-button close-app" onClick={onClose}>
        <Icon name="close" size={16} />
        アプリを閉じる
      </button>
    </header>
    {children}
  </main>
);
