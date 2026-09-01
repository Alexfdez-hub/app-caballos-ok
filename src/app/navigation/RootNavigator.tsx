import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { ActivityIndicator, StyleSheet, View } from 'react-native';

import { useAuth } from '../../features/auth/useAuth';
import { useIdentity } from '../../features/identity/useIdentity';
import AuthLinkErrorScreen from '../../screens/AuthLinkErrorScreen';
import AuthScreen from '../../screens/AuthScreen';
import ForgotPasswordScreen from '../../screens/ForgotPasswordScreen';
import IdentityErrorScreen from '../../screens/IdentityErrorScreen';
import IdentityOnboardingScreen from '../../screens/IdentityOnboardingScreen';
import UpdatePasswordScreen from '../../screens/UpdatePasswordScreen';
import { AuthenticatedTabs } from './AuthenticatedTabs';
import type {
  PublicStackParamList,
  RecoveryStackParamList,
} from './types';

const PublicStack = createNativeStackNavigator<PublicStackParamList>();
const RecoveryStack = createNativeStackNavigator<RecoveryStackParamList>();
const OnboardingStack = createNativeStackNavigator<{
  IdentityOnboarding: undefined;
}>();
const IdentityErrorStack = createNativeStackNavigator<{
  IdentityError: undefined;
}>();

export function RootNavigator() {
  const { session, isRestoringSession, isPasswordRecovery, authLinkError } =
    useAuth();
  const { identity, isLoadingIdentity, identityError } = useIdentity();

  if (
    isRestoringSession ||
    (session && isLoadingIdentity && !isPasswordRecovery && !authLinkError)
  ) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color="#111" />
      </View>
    );
  }

  if (authLinkError) {
    return <AuthLinkErrorScreen />;
  }

  if (session && isPasswordRecovery) {
    return (
      <NavigationContainer>
        <RecoveryStack.Navigator>
          <RecoveryStack.Screen
            name="UpdatePassword"
            component={UpdatePasswordScreen}
            options={{ headerShown: false }}
          />
        </RecoveryStack.Navigator>
      </NavigationContainer>
    );
  }

  if (!session) {
    return (
      <NavigationContainer>
        <PublicStack.Navigator>
          <PublicStack.Screen
            name="Auth"
            component={AuthScreen}
            options={{ headerShown: false }}
          />
          <PublicStack.Screen
            name="ForgotPassword"
            component={ForgotPasswordScreen}
            options={{ headerShown: false }}
          />
        </PublicStack.Navigator>
      </NavigationContainer>
    );
  }

  if (identityError || !identity) {
    return (
      <NavigationContainer>
        <IdentityErrorStack.Navigator>
          <IdentityErrorStack.Screen
            name="IdentityError"
            component={IdentityErrorScreen}
            options={{ headerShown: false }}
          />
        </IdentityErrorStack.Navigator>
      </NavigationContainer>
    );
  }

  if (!identity.isComplete) {
    return (
      <NavigationContainer>
        <OnboardingStack.Navigator>
          <OnboardingStack.Screen
            name="IdentityOnboarding"
            component={IdentityOnboardingScreen}
            options={{ headerShown: false }}
          />
        </OnboardingStack.Navigator>
      </NavigationContainer>
    );
  }

  return (
    <NavigationContainer>
      <AuthenticatedTabs />
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
