import * as React from 'react';

import { StyleSheet, View, Button } from 'react-native';
import { multiply } from 'video-package';
import { loadCallWithId } from 'video-package';

export default function App() {
  const [result, setResult] = React.useState<number | undefined>();

  return (
    <View style={styles.container}>
      <Button
        title='Call'
        onPress={() => loadCallWithId('rya8PwW1',true) } 
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
