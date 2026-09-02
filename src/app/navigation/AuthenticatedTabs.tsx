import Ionicons from '@expo/vector-icons/Ionicons';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import type { ComponentProps } from 'react';

import ActivityScreen from '../../screens/ActivityScreen';
import EditIdentityScreen from '../../screens/EditIdentityScreen';
import EditRiderProfileScreen from '../../screens/EditRiderProfileScreen';
import EquestrianPassportScreen from '../../screens/EquestrianPassportScreen';
import ExploreScreen from '../../screens/ExploreScreen';
import GuardianRelationshipsScreen from '../../screens/GuardianRelationshipsScreen';
import HomeScreen from '../../screens/HomeScreen';
import MyCentersScreen from '../../screens/MyCentersScreen';
import MyEquinesScreen from '../../screens/MyEquinesScreen';
import MyManagedEquinesScreen from '../../screens/MyManagedEquinesScreen';
import ProfileScreen from '../../screens/ProfileScreen';
import { colors } from '../ui/theme';
import type {
  ActivityStackParamList,
  AuthenticatedTabParamList,
  ExploreStackParamList,
  HomeStackParamList,
  PassportStackParamList,
  ProfileStackParamList,
} from './types';

const Tab = createBottomTabNavigator<AuthenticatedTabParamList>();
const HomeStackNavigator = createNativeStackNavigator<HomeStackParamList>();
const ExploreStackNavigator =
  createNativeStackNavigator<ExploreStackParamList>();
const ActivityStackNavigator =
  createNativeStackNavigator<ActivityStackParamList>();
const PassportStackNavigator =
  createNativeStackNavigator<PassportStackParamList>();
const ProfileStackNavigator =
  createNativeStackNavigator<ProfileStackParamList>();

function HomeStack() {
  return (
    <HomeStackNavigator.Navigator>
      <HomeStackNavigator.Screen
        name="Home"
        component={HomeScreen}
        options={{ headerShown: false }}
      />
    </HomeStackNavigator.Navigator>
  );
}

function ExploreStack() {
  return (
    <ExploreStackNavigator.Navigator>
      <ExploreStackNavigator.Screen
        name="Explore"
        component={ExploreScreen}
        options={{ headerShown: false }}
      />
    </ExploreStackNavigator.Navigator>
  );
}

function ActivityStack() {
  return (
    <ActivityStackNavigator.Navigator>
      <ActivityStackNavigator.Screen
        name="Activity"
        component={ActivityScreen}
        options={{ headerShown: false }}
      />
    </ActivityStackNavigator.Navigator>
  );
}

function PassportStack() {
  return (
    <PassportStackNavigator.Navigator>
      <PassportStackNavigator.Screen
        name="Passport"
        component={EquestrianPassportScreen}
        options={{ headerShown: false }}
      />
      <PassportStackNavigator.Screen
        name="EditRiderProfile"
        component={EditRiderProfileScreen}
        options={{
          title: 'Perfil de jinete',
          headerTintColor: colors.text,
          headerStyle: { backgroundColor: colors.background },
          headerShadowVisible: false,
        }}
      />
    </PassportStackNavigator.Navigator>
  );
}

function ProfileStack() {
  return (
    <ProfileStackNavigator.Navigator>
      <ProfileStackNavigator.Screen
        name="Profile"
        component={ProfileScreen}
        options={{ headerShown: false }}
      />
      <ProfileStackNavigator.Screen
        name="EditIdentity"
        component={EditIdentityScreen}
        options={{
          title: 'Editar datos básicos',
          headerTintColor: colors.text,
          headerStyle: { backgroundColor: colors.background },
          headerShadowVisible: false,
        }}
      />
      <ProfileStackNavigator.Screen
        name="GuardianRelationships"
        component={GuardianRelationshipsScreen}
        options={{
          title: 'Tutor y menores',
          headerTintColor: colors.text,
          headerStyle: { backgroundColor: colors.background },
          headerShadowVisible: false,
        }}
      />
      <ProfileStackNavigator.Screen
        name="MyCenters"
        component={MyCentersScreen}
        options={{
          title: 'Mis centros',
          headerTintColor: colors.text,
          headerStyle: { backgroundColor: colors.background },
          headerShadowVisible: false,
        }}
      />
      <ProfileStackNavigator.Screen
        name="MyEquines"
        component={MyEquinesScreen}
        options={{
          title: 'Mis equinos',
          headerTintColor: colors.text,
          headerStyle: { backgroundColor: colors.background },
          headerShadowVisible: false,
        }}
      />
      <ProfileStackNavigator.Screen
        name="MyManagedEquines"
        component={MyManagedEquinesScreen}
        options={{
          title: 'Equinos que gestiono',
          headerTintColor: colors.text,
          headerStyle: { backgroundColor: colors.background },
          headerShadowVisible: false,
        }}
      />
    </ProfileStackNavigator.Navigator>
  );
}

type IoniconName = ComponentProps<typeof Ionicons>['name'];

function tabIconName(
  routeName: keyof AuthenticatedTabParamList,
  focused: boolean,
): IoniconName {
  switch (routeName) {
    case 'HomeTab':
      return focused ? 'home' : 'home-outline';
    case 'ExploreTab':
      return focused ? 'compass' : 'compass-outline';
    case 'ActivityTab':
      return focused ? 'calendar' : 'calendar-outline';
    case 'PassportTab':
      return focused ? 'ribbon' : 'ribbon-outline';
    case 'ProfileTab':
      return focused ? 'person' : 'person-outline';
  }
}

export function AuthenticatedTabs() {
  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        headerShown: false,
        tabBarActiveTintColor: colors.text,
        tabBarInactiveTintColor: colors.disabled,
        tabBarStyle: {
          backgroundColor: colors.surface,
          borderTopColor: colors.border,
        },
        tabBarLabelStyle: {
          fontSize: 11,
          fontWeight: '600',
        },
        tabBarIcon: ({ color, focused, size }) => (
          <Ionicons
            color={color}
            name={tabIconName(route.name, focused)}
            size={size}
          />
        ),
      })}
    >
      <Tab.Screen
        name="HomeTab"
        component={HomeStack}
        options={{ title: 'Inicio' }}
      />
      <Tab.Screen
        name="ExploreTab"
        component={ExploreStack}
        options={{ title: 'Explorar' }}
      />
      <Tab.Screen
        name="ActivityTab"
        component={ActivityStack}
        options={{ title: 'Actividad' }}
      />
      <Tab.Screen
        name="PassportTab"
        component={PassportStack}
        options={{ title: 'Pasaporte' }}
      />
      <Tab.Screen
        name="ProfileTab"
        component={ProfileStack}
        options={{ title: 'Perfil' }}
      />
    </Tab.Navigator>
  );
}
