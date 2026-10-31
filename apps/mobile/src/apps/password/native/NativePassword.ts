import type {TurboModule} from 'react-native';
import {TurboModuleRegistry} from 'react-native';

export interface Spec extends TurboModule {
  copyText(value: string): Promise<boolean>;
  randomBytes(count: number): Promise<number[]>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('NativePassword');
