import React, {useCallback, useState} from 'react';
import {Alert, BackHandler, StatusBar, StyleSheet, Text, View} from 'react-native';
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
      <View style={appStyles.header}><Text style={appStyles.brand} onPress={() => navigate('home')}>prelis.</Text><Text style={styles.muted}>{page === 'home' ? 'アプリを選択' : pages.find(item => item.id === page)?.label}</Text></View>
      {page === 'home' && <View style={styles.content}><Text style={styles.heading}>アプリを選択</Text>{pages.map(item => <Button key={item.id} label={item.label} onPress={() => navigate(item.id)} />)}</View>}
      {page === 'diary' && <Diary onState={onDiaryState} />}
      <View style={page === 'timer' ? appStyles.timerVisible : appStyles.timerHidden}><Timer /></View>
      {page === 'password' && <Password />}
      <View style={appStyles.tabs}><Button label="ホーム" selected={page === 'home'} onPress={() => navigate('home')} />{pages.map(item => <Button key={item.id} label={item.label} selected={page === item.id} onPress={() => navigate(item.id)} />)}</View>
    </SafeAreaView>
  </SafeAreaProvider>;
}
const appStyles = StyleSheet.create({
  header: {paddingHorizontal: 20, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: '#eaecf0', flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between'},
  brand: {fontSize: 26, color: colors.accent, fontWeight: '800'},
  timerVisible: {flex: 1},
  timerHidden: {display: 'none'},
  tabs: {flexDirection: 'row', justifyContent: 'space-around', padding: 6, borderTopWidth: 1, borderTopColor: '#eaecf0'},
});
export default App;
