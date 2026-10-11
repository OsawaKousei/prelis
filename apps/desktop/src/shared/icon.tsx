type IconName =
  | 'diary'
  | 'timer'
  | 'password'
  | 'close'
  | 'left'
  | 'right'
  | 'check'
  | 'save'
  | 'arrow';
const paths: Record<IconName, string> = {
  diary:
    'M5 3h12a2 2 0 0 1 2 2v16H6a3 3 0 0 1-3-3V5a2 2 0 0 1 2-2Zm0 14h14M7 3v14M10 7h5M10 10h4',
  timer:
    'M9 2h6M12 2v3M18 5l2 2M12 9v5l3 2M20 14a8 8 0 1 1-16 0 8 8 0 0 1 16 0Z',
  password: 'M5 11V7a7 7 0 0 1 14 0v4M5 11h14v10H5V11Zm7 4v2',
  close: 'm6 6 12 12M18 6 6 18',
  left: 'm14 6-6 6 6 6',
  right: 'm10 6 6 6-6 6',
  check: 'm5 12 4 4L19 6',
  save: 'M5 3h12l4 4v14H3V3h2Zm2 0v6h10V3M7 21v-8h10v8',
  arrow: 'M4 12h16m-6-6 6 6-6 6',
};
export const Icon = ({
  name,
  size = 20,
}: {
  readonly name: IconName;
  readonly size?: number;
}) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="1.5"
    strokeLinecap="round"
    strokeLinejoin="round"
    aria-hidden="true"
  >
    <path d={paths[name]} />
  </svg>
);
