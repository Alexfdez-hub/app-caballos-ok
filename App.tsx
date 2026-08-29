import { RootNavigator } from './src/app/navigation/RootNavigator';
import { AuthProvider } from './src/app/providers/AuthProvider';

export default function App() {
  return (
    <AuthProvider>
      <RootNavigator />
    </AuthProvider>
  );
}
