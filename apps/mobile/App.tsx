import React from 'react';
import {StatusBar} from 'react-native';
import {SafeAreaProvider} from 'react-native-safe-area-context';
import {Shell} from './src/shell/shell';

function App() {
  return <SafeAreaProvider>
    <StatusBar barStyle="dark-content" />
    <Shell />
  </SafeAreaProvider>;
}

export default App;
