import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { ActivityIndicator, StyleSheet, View } from 'react-native';

import { useAuth } from '../../features/auth/useAuth';
import BaselineScreen from '../../screens/BaselineScreen';

const Stack = createNativeStackNavigator();

export function RootNavigator() {
  const { session, isRestoringSession } = useAuth();

  if (isRestoringSession) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color="#111" />
      </View>
    );
  }

  return (
    <NavigationContainer>
      <Stack.Navigator key={session ? 'authenticated-shell' : 'public-shell'}>
        <Stack.Screen
          name="Baseline"
          component={BaselineScreen}
          options={{ headerShown: false }}
        />
      </Stack.Navigator>
    </NavigationContainer>
  );
}

const styles = StyleSheet.create({
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#f5f5f5',
  },
});
