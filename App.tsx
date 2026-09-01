import { SafeAreaProvider } from 'react-native-safe-area-context';

import { RootNavigator } from './src/app/navigation/RootNavigator';
import { AuthProvider } from './src/app/providers/AuthProvider';
import { IdentityProvider } from './src/features/identity/IdentityProvider';

export default function App() {
  return (
    <SafeAreaProvider>
      <AuthProvider>
        <IdentityProvider>
          <RootNavigator />
        </IdentityProvider>
      </AuthProvider>
    </SafeAreaProvider>
  );
}
