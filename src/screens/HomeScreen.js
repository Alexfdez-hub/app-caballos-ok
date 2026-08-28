import React from 'react';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { Ionicons } from '@expo/vector-icons';
import { View, Text } from 'react-native';

// Importamos las pantallas reales
import SearchScreen from './SearchScreen';
import ProfileScreen from './ProfileScreen';
import BookingsScreen from './BookingsScreen';

const Tab = createBottomTabNavigator();

// Pantalla temporal para reservas (hasta que hagamos ese módulo)
function BookingsDummy() {
  return <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center' }}><Text>Tus reservas activas</Text></View>;
}

export default function HomeScreen() {
  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        headerShown: true,
        tabBarIcon: ({ focused, color, size }) => {
          let iconName;
          if (route.name === 'Buscar') iconName = focused ? 'search' : 'search-outline';
          else if (route.name === 'Reservas') iconName = focused ? 'calendar' : 'calendar-outline';
          else if (route.name === 'Perfil') iconName = focused ? 'person' : 'person-outline';
          return <Ionicons name={iconName} size={size} color={color} />;
        },
        tabBarActiveTintColor: '#111',
        tabBarInactiveTintColor: 'gray',
      })}
    >
      <Tab.Screen name="Buscar" component={SearchScreen} />
      <Tab.Screen name="Reservas" component={BookingsScreen} />
      <Tab.Screen name="Perfil" component={ProfileScreen} />
      
    </Tab.Navigator>
  );
}