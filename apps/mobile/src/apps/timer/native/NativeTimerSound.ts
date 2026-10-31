import type {TurboModule} from 'react-native';
import {TurboModuleRegistry} from 'react-native';

export type Sound = {id: string; name: string; mimeType: string};

export interface Spec extends TurboModule {
  readLibrary(): Promise<string | null>;
  writeLibrary(content: string): Promise<boolean>;
  pickSound(): Promise<Sound | null>;
  deleteSoundFile(id: string): Promise<boolean>;
  playSound(id: string, loop: boolean): Promise<boolean>;
  stopSound(): Promise<boolean>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('NativeTimerSound');
