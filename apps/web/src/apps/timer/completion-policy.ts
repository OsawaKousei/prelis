export type CompletionMode = 'running' | 'audible' | 'silent';

export const completionMode = (
  deadline: number,
  now: number,
  visible: boolean,
  wasHidden: boolean,
): CompletionMode => {
  if (now < deadline) return 'running';
  return visible && !wasHidden ? 'audible' : 'silent';
};
