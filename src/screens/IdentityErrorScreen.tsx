import {
  Pressable,
  SafeAreaView,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import { signOut } from '../features/auth/authService';
import { useIdentity } from '../features/identity/useIdentity';

export default function IdentityErrorScreen() {
  const { refreshIdentity } = useIdentity();

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.content}>
        <Text style={styles.title}>No pudimos cargar tu identidad</Text>
        <Text style={styles.description}>
          Comprueba la conexión e inténtalo de nuevo.
        </Text>

        <Pressable
          accessibilityRole="button"
          onPress={refreshIdentity}
          style={({ pressed }) => [
            styles.primaryButton,
            pressed && styles.buttonPressed,
          ]}
        >
          <Text style={styles.primaryButtonText}>Reintentar</Text>
        </Pressable>

        <Pressable
          accessibilityRole="button"
          onPress={signOut}
          style={({ pressed }) => [
            styles.secondaryButton,
            pressed && styles.buttonPressed,
          ]}
        >
          <Text style={styles.secondaryButtonText}>Cerrar sesión</Text>
        </Pressable>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  content: {
    flex: 1,
    justifyContent: 'center',
    padding: 24,
  },
  title: {
    color: '#111',
    fontSize: 28,
    fontWeight: '700',
  },
  description: {
    marginTop: 10,
    color: '#555',
    fontSize: 16,
  },
  primaryButton: {
    minHeight: 50,
    marginTop: 24,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
    backgroundColor: '#111',
  },
  secondaryButton: {
    minHeight: 50,
    marginTop: 10,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonPressed: {
    opacity: 0.8,
  },
  primaryButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  secondaryButtonText: {
    color: '#333',
    fontSize: 15,
    fontWeight: '600',
  },
});
