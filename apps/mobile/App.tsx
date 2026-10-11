import React, {useCallback, useState} from 'react';
import {Alert, BackHandler, Pressable, StatusBar, StyleSheet, Text, View} from 'react-native';
import {SafeAreaProvider, SafeAreaView} from 'react-native-safe-area-context';
import {Diary} from './src/Diary';
import {Password} from './src/Password';
import {Timer} from './src/Timer';
import {Button, colors, styles} from './src/ui';

type Page = 'home' | 'diary' | 'timer' | 'password';
const pages: {id: Exclude<Page, 'home'>; label: string}[] = [
  {id: 'diary', label: 'Diary'}, {id: 'timer', label: 'Timer'}, {id: 'password', label: 'Password'},
];

function App() {
  const [page, setPage] = useState<Page>('home');
  const [diaryDirty, setDiaryDirty] = useState(false);
  const [diarySaving, setDiarySaving] = useState(false);
  const onDiaryState = useCallback((dirty: boolean, saving: boolean) => {setDiaryDirty(dirty); setDiarySaving(saving);}, []);
  const navigate = useCallback((next: Page) => {
    if (next === page) return;
    if (page === 'diary' && diarySaving) return;
    if (page === 'diary' && diaryDirty) {
      Alert.alert('未保存の変更があります', '変更を破棄しますか？入力内容は保存されません。', [
        {text: 'キャンセル', style: 'cancel'}, {text: '変更を破棄', style: 'destructive', onPress: () => setPage(next)},
      ]);
      return;
    }
    setPage(next);
  }, [page, diaryDirty, diarySaving]);
  React.useEffect(() => {
    const listener = BackHandler.addEventListener('hardwareBackPress', () => {
      if (page === 'home') return false;
      navigate('home');
      return true;
    });
    return () => listener.remove();
  }, [page, navigate]);
  return <SafeAreaProvider><StatusBar barStyle="dark-content" />
    <SafeAreaView style={styles.screen}>
      <View style={appStyles.header}><Pressable accessibilityRole="button" accessibilityLabel="ホームへ" onPress={() => navigate('home')}><Text style={appStyles.brand}>prelis<Text style={appStyles.brandDot}>.</Text></Text></Pressable><Text style={appStyles.location}>{page === 'home' ? 'ワークスペース' : pages.find(item => item.id === page)?.label}</Text></View>
      {page === 'home' && <View style={styles.content}><View style={appStyles.homeIntro}><Text style={styles.heading}>アプリを選択</Text><Text style={styles.muted}>使いたい機能を選んでください。</Text></View><View>{pages.map(item => <Button key={item.id} label={item.label} variant="launch" onPress={() => navigate(item.id)} />)}</View></View>}
      {page === 'diary' && <Diary onState={onDiaryState} />}
      <View style={page === 'timer' ? appStyles.timerVisible : appStyles.timerHidden}><Timer /></View>
      {page === 'password' && <Password />}
      <View style={appStyles.tabs}><Button label="ホーム" variant="tab" selected={page === 'home'} onPress={() => navigate('home')} />{pages.map(item => <Button key={item.id} label={item.label} variant="tab" selected={page === item.id} onPress={() => navigate(item.id)} />)}</View>
    </SafeAreaView>
  </SafeAreaProvider>;
}
const appStyles = StyleSheet.create({
  header: {paddingHorizontal: 24, paddingVertical: 12, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: colors.line, backgroundColor: colors.surface, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between'},
  brand: {fontSize: 25, letterSpacing: -0.5, color: colors.ink, fontWeight: '700'},
  brandDot: {color: colors.accent},
  location: {fontSize: 12, letterSpacing: 1.2, color: colors.muted},
  homeIntro: {gap: 9, paddingTop: 16, paddingBottom: 14},
  timerVisible: {flex: 1},
  timerHidden: {display: 'none'},
  tabs: {flexDirection: 'row', justifyContent: 'space-around', paddingHorizontal: 10, paddingTop: 5, backgroundColor: colors.surface, borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.line},
});
export default App;
