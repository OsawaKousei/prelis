// A cancellable UI navigation event. Apps retain ownership of their drafts and dialogs.
// No dirty state or app lifecycle is maintained by the Shell.
export const BEFORE_APP_NAVIGATE = 'prelis:before-app-navigate';
export const requestAppNavigation = (navigate: () => void) => {
  const event = new CustomEvent(BEFORE_APP_NAVIGATE, {
    cancelable: true,
    detail: navigate,
  });
  if (window.dispatchEvent(event)) navigate();
};
