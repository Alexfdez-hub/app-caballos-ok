import { Pressable, SafeAreaView, StyleSheet, Text, View } from 'react-native';

import { useAuth } from '../features/auth/useAuth';

export default function AuthLinkErrorScreen() {
  const { authLinkError, clearAuthLinkError } = useAuth();

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.content}>
        <Text style={styles.eyebrow}>ACCESO</Text>
        <Text style={styles.title}>Enlace no válido</Text>
        <Text accessibilityRole="alert" style={styles.description}>
          {authLinkError ??
            'El enlace de acceso no es válido o ha caducado. Solicita uno nuevo.'}
        </Text>

        <Pressable
          accessibilityRole="button"
          onPress={clearAuthLinkError}
          style={({ pressed }) => [
            styles.primaryButton,
            pressed && styles.buttonPressed,
          ]}
        >
          <Text style={styles.primaryButtonText}>Volver al acceso</Text>
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
  eyebrow: {
    marginBottom: 8,
    color: '#666',
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 1.5,
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
    lineHeight: 23,
  },
  primaryButton: {
    minHeight: 50,
    marginTop: 24,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
    backgroundColor: '#111',
  },
  buttonPressed: {
    opacity: 0.8,
  },
  primaryButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
});
