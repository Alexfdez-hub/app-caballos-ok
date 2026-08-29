import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { ActivityIndicator, StyleSheet, View } from 'react-native';

import { useAuth } from '../../features/auth/useAuth';
import HomeScreen from '../../screens/HomeScreen';
import HorseDetailScreen from '../../screens/HorseDetailScreen';
import LoginScreen from '../../screens/LoginScreen';
import OwnerEditHorseScreen from '../../screens/OwnerEditHorseScreen';
import OwnerHorsesScreen from '../../screens/OwnerHorsesScreen';
import OwnerRegisterHorseScreen from '../../screens/OwnerRegisterHorseScreen';

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
      <Stack.Navigator key={session ? 'authenticated' : 'unauthenticated'}>
        {session ? (
          <>
            <Stack.Screen
              name="Home"
              component={HomeScreen}
              options={{ headerShown: false }}
            />
            <Stack.Screen
              name="HorseDetail"
              component={HorseDetailScreen}
              options={{
                title: 'Detalles del Caballo',
                headerBackTitle: 'Volver',
              }}
            />
            <Stack.Screen
              name="RegisterHorse"
              component={OwnerRegisterHorseScreen}
              options={{ title: 'Nuevo Caballo', headerBackTitle: 'Volver' }}
            />
            <Stack.Screen
              name="OwnerHorses"
              component={OwnerHorsesScreen}
              options={{
                title: 'Mis Caballos Registrados',
                headerBackTitle: 'Volver',
              }}
            />
            <Stack.Screen
              name="OwnerEditHorse"
              component={OwnerEditHorseScreen}
              options={{
                title: 'Editar Caballo',
                headerBackTitle: 'Volver',
              }}
            />
          </>
        ) : (
          <Stack.Screen
            name="Login"
            component={LoginScreen}
            options={{ headerShown: false }}
          />
        )}
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
