import type {TurboModule} from 'react-native';
import {TurboModuleRegistry} from 'react-native';

export interface Spec extends TurboModule {
  readDiary(date: string): Promise<string>;
  saveDiary(date: string, content: string): Promise<boolean>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('NativeDiary');
