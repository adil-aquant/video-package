import * as React from 'react';
import { StyleSheet, View, Button } from 'react-native';
import { loadCallWithId } from 'video-package';

export default function App() {
  const [result, setResult] = React.useState<number | undefined>();

  return (
    <View style={styles.container}>
      <Button
        title='Call'
        onPress={() => loadCallWithId('vOD20Rnu',true,'https://video-triage-staging.herokuapp.com') } 
      />
   </View>
);
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  box: {
    width: 60,
    height: 60,
    marginVertical: 20,
  },
});
