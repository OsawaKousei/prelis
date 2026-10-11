import {useState} from 'react';
import {greet} from '@prelis/core';
import {StatusBar, StyleSheet, Text, TextInput} from 'react-native';
import {SafeAreaProvider, SafeAreaView} from 'react-native-safe-area-context';

function App() {
  const [name, setName] = useState('Prelis');

  return (
    <SafeAreaProvider>
      <StatusBar barStyle="dark-content" />
      <SafeAreaView style={styles.container}>
        <Text style={styles.title}>Prelis</Text>
        <Text style={styles.text}>Name</Text>
        <TextInput
          accessibilityLabel="Name"
          style={styles.input}
          value={name}
          onChangeText={setName}
          placeholder="Enter a name..."
          placeholderTextColor="#666666"
        />
        <Text testID="greeting" style={styles.text}>
          {greet(name)}
        </Text>
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 24,
    backgroundColor: '#ffffff',
    gap: 16,
  },
  title: {
    fontSize: 32,
    fontWeight: 'bold',
    color: '#111111',
  },
  text: {
    fontSize: 18,
    color: '#111111',
  },
  input: {
    borderWidth: 1,
    borderColor: '#777777',
    borderRadius: 8,
    padding: 12,
    color: '#111111',
  },
});

export default App;
