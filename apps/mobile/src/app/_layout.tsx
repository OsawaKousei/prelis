import React from 'react';
import {Image, StyleSheet, Text, View} from 'react-native';
import {Tabs} from 'expo-router';
import {StatusBar} from 'expo-status-bar';
import {SafeAreaProvider} from 'react-native-safe-area-context';
import {TimerProvider} from '../apps/timer/timer-provider';
import {Icon, type IconName} from '../shared/icon';
import {colors} from '../shared/theme';

const tabs: {name: string; title: string; icon: IconName}[] = [
  {name: 'index', title: 'ホーム', icon: 'home'},
  {name: 'diary', title: 'Diary', icon: 'diary'},
  {name: 'timer', title: 'Timer', icon: 'timer'},
  {name: 'password', title: 'Password', icon: 'password'},
];

export const unstable_settings = {initialRouteName: 'index'};

function Brand() {
  return <View style={styles.brand}>
    <Image source={require('@prelis/icons/assets/brand.png')} style={styles.mark} accessible={false} />
    <Text style={styles.label}>prelis<Text style={styles.dot}>.</Text></Text>
  </View>;
}

export default function RootLayout() {
  return <SafeAreaProvider>
    <StatusBar style="dark" />
    <TimerProvider>
      <Tabs backBehavior="initialRoute" screenOptions={{
        headerTitle: Brand,
        headerStyle: {backgroundColor: colors.surface},
        sceneStyle: {backgroundColor: colors.background},
        tabBarActiveTintColor: colors.accent,
        tabBarInactiveTintColor: colors.muted,
        tabBarStyle: {backgroundColor: colors.surface, borderTopColor: colors.line},
        tabBarHideOnKeyboard: true,
      }}>
        {tabs.map(tab => <Tabs.Screen key={tab.name} name={tab.name} options={{
          title: tab.title,
          tabBarButtonTestID: `tab-${tab.name}`,
          tabBarIcon: ({focused, size}) => <Icon name={tab.icon} color={focused ? colors.accent : colors.muted} size={size} />,
        }} />)}
      </Tabs>
    </TimerProvider>
  </SafeAreaProvider>;
}

const styles = StyleSheet.create({
  brand: {flexDirection: 'row', alignItems: 'center', gap: 8},
  mark: {width: 30, height: 30},
  label: {fontSize: 25, fontWeight: '700', color: colors.ink},
  dot: {color: colors.accent},
});
