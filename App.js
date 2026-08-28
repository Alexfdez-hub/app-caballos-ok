import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';

import LoginScreen from './src/screens/LoginScreen';
import HomeScreen from './src/screens/HomeScreen';
import HorseDetailScreen from './src/screens/HorseDetailScreen';
import OwnerRegisterHorseScreen from './src/screens/OwnerRegisterHorseScreen';
import OwnerHorsesScreen from './src/screens/OwnerHorsesScreen'; // NUEVO: Importación que faltaba
import OwnerEditHorseScreen from './src/screens/OwnerEditHorseScreen';
const Stack = createNativeStackNavigator();

export default function App() {
  return (
    <NavigationContainer>
      <Stack.Navigator initialRouteName="Login">
        <Stack.Screen name="Login" component={LoginScreen} options={{ headerShown: false }} />
        <Stack.Screen name="Home" component={HomeScreen} options={{ headerShown: false }} />
        <Stack.Screen 
          name="HorseDetail" 
          component={HorseDetailScreen} 
          options={{ title: 'Detalles del Caballo', headerBackTitle: 'Volver' }} 
        />
        <Stack.Screen 
          name="RegisterHorse" 
          component={OwnerRegisterHorseScreen} 
          options={{ title: 'Nuevo Caballo', headerBackTitle: 'Volver' }} 
        />
        <Stack.Screen 
          name="OwnerHorses" 
          component={OwnerHorsesScreen} 
          options={{ title: 'Mis Caballos Registrados', headerBackTitle: 'Volver' }} 
        />
         <Stack.Screen 
          name="OwnerEditHorse" 
          component={OwnerEditHorseScreen} 
          options={{ title: 'Editar Caballo', headerBackTitle: 'Volver' }} 
        />
      </Stack.Navigator>
    </NavigationContainer>
  );
}