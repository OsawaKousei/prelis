import React, {useState} from 'react';
import {Pressable, StyleSheet, Text, View} from 'react-native';
import * as Linking from 'expo-linking';
import {router} from 'expo-router';
import {Button, colors, Page, styles} from '../shared/ui';

const privacyPolicyUrl = 'https://prelis.prj.kupac.co.jp/privacy';

export default function HomeScreen() {
  const [privacyError, setPrivacyError] = useState(false);
  return <Page id="home">
    <View style={{gap: 9}}>
      <Text style={styles.heading}>アプリを選択</Text>
      <Text style={styles.muted}>使いたい機能を選んでください。</Text>
    </View>
    <View>
      <Button label="Diary" icon="diary" variant="launch" onPress={() => router.navigate('/diary')} />
      <Button label="Timer" icon="timer" variant="launch" onPress={() => router.navigate('/timer')} />
      <Button label="Password" icon="password" variant="launch" onPress={() => router.navigate('/password')} />
    </View>
    <Pressable
      accessibilityRole="link"
      accessibilityLabel="プライバシーポリシー"
      accessibilityHint="ブラウザーで開きます"
      style={({pressed}) => [homeStyles.privacyLink, pressed && {opacity: 0.68}]}
      onPress={() => {
        setPrivacyError(false);
        Linking.openURL(privacyPolicyUrl).catch(() => setPrivacyError(true));
      }}>
      <Text style={homeStyles.privacyLabel}>プライバシーポリシー</Text>
    </Pressable>
    {privacyError && <Text accessibilityRole="alert" accessibilityLiveRegion="polite" style={styles.error}>ブラウザーを開けませんでした。もう一度お試しください。</Text>}
    <Text style={styles.muted}>v0.1.4</Text>
  </Page>;
}

const homeStyles = StyleSheet.create({
  privacyLink: {alignSelf: 'flex-start', minHeight: 44, justifyContent: 'center'},
  privacyLabel: {fontSize: 14, lineHeight: 20, color: colors.accent, textDecorationLine: 'underline'},
});
