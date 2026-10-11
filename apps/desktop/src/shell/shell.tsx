import { useState } from 'react';
import { apps } from './apps';
import { Sidebar } from './sidebar';
import { AppFrame } from './app-frame';
import { requestAppNavigation } from './navigation';
import { Icon } from '../shared/icon';
import './shell.css';
export const Shell = () => {
  const [activeId, setActiveId] = useState<string | null>(null);
  const active = apps.find((app) => app.id === activeId);
  const navigate = (id: string | null) => {
    if (id !== activeId) requestAppNavigation(() => setActiveId(id));
  };
  return (
    <div className="shell">
      <Sidebar apps={apps} activeId={activeId} onSelect={navigate} />
      {apps.map((app) => {
        const isActive = app.id === activeId;
        if (!isActive && !app.keepMounted) return null;
        const App = app.component;
        return (
          <AppFrame
            key={app.id}
            name={app.name}
            onClose={() => navigate(null)}
            hidden={!isActive}
          >
            <App />
          </AppFrame>
        );
      })}
      {!active && (
        <main className="workspace-empty">
          <h1>アプリを選択</h1>
          <div className="launch-list">
            {apps.map((app) => (
              <button key={app.id} onClick={() => navigate(app.id)}>
                <Icon name={app.icon} size={28} />
                <span>
                  <strong>{app.name}</strong>
                </span>
                <Icon name="arrow" />
              </button>
            ))}
          </div>
        </main>
      )}
    </div>
  );
};
