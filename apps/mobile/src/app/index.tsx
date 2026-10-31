import React from 'react';
import {ScrollView, Text, View} from 'react-native';
import {router} from 'expo-router';
import {Button, styles} from '../shared/ui';

export default function HomeScreen() {
  return <ScrollView contentContainerStyle={styles.content}>
    <View style={{gap: 9}}>
      <Text style={styles.heading}>アプリを選択</Text>
      <Text style={styles.muted}>使いたい機能を選んでください。</Text>
    </View>
    <View>
      <Button label="Diary" icon="diary" variant="launch" onPress={() => router.navigate('/diary')} />
      <Button label="Timer" icon="timer" variant="launch" onPress={() => router.navigate('/timer')} />
      <Button label="Password" icon="password" variant="launch" onPress={() => router.navigate('/password')} />
    </View>
    <Text style={styles.muted}>v0.1.3</Text>
  </ScrollView>;
}
