const databaseName = 'prelis-web';
const databaseVersion = 1;

let opening: Promise<IDBDatabase> | null = null;

export const openDatabase = (): Promise<IDBDatabase> => {
  if (opening) return opening;
  opening = new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open(databaseName, databaseVersion);
    let blocked = false;
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains('diaries')) database.createObjectStore('diaries');
      if (!database.objectStoreNames.contains('sounds')) database.createObjectStore('sounds', { keyPath: 'id' });
      if (!database.objectStoreNames.contains('settings')) database.createObjectStore('settings');
    };
    request.onsuccess = () => {
      if (blocked) {
        request.result.close();
        return;
      }
      request.result.onversionchange = () => {
        request.result.close();
        opening = null;
      };
      resolve(request.result);
    };
    request.onerror = () => reject(request.error);
    request.onblocked = () => {
      blocked = true;
      reject(new Error('保存先を開けませんでした。別のタブを閉じて再試行してください。'));
    };
  }).catch((error: unknown) => {
    opening = null;
    throw error;
  });
  return opening;
};

export const requestValue = <T>(request: IDBRequest<T>): Promise<T> =>
  new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });

export const transactionDone = (transaction: IDBTransaction): Promise<void> =>
  new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error);
    transaction.onabort = () => reject(transaction.error ?? new Error('保存処理が中断されました。'));
  });
