/**
 * @format
 */

import React from 'react';
import ReactTestRenderer from 'react-test-renderer';
import {TextInput} from 'react-native';
import App from '../App';

// Supply native window metrics in the Node.js test environment.
jest.mock('react-native-safe-area-context', () =>
  require('react-native-safe-area-context/jest/mock').default,
);

test('renders shared core logic and updates it when the name changes', async () => {
  let renderer: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });
  expect(renderer!.root.findByProps({testID: 'greeting'}).props.children).toBe(
    'Hello, Prelis!',
  );

  await ReactTestRenderer.act(() => {
    renderer!.root.findByType(TextInput).props.onChangeText('Android');
  });
  expect(renderer!.root.findByProps({testID: 'greeting'}).props.children).toBe(
    'Hello, Android!',
  );
  await ReactTestRenderer.act(() => {
    renderer!.unmount();
  });
});
