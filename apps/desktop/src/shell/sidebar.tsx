import { Icon } from '../shared/icon';
import brand from '@prelis/icons/assets/brand.png';
import type { AppDefinition } from './apps';
type Props = {
  readonly apps: readonly AppDefinition[];
  readonly activeId: string | null;
  readonly onSelect: (id: string) => void;
};
export const Sidebar = ({ apps, activeId, onSelect }: Props) => (
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
      <span className="version">v0.1.3</span>
    </div>
  </aside>
);
