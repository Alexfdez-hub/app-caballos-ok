import { useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  SafeAreaView,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import { useAuth } from '../features/auth/useAuth';
import { supabase } from '../services/supabase/client';

export default function BaselineScreen() {
  const { session } = useAuth();
  const [isSigningOut, setIsSigningOut] = useState(false);

  async function handleSignOut() {
    setIsSigningOut(true);
    await supabase.auth.signOut();
    setIsSigningOut(false);
  }

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.content}>
        <Text style={styles.eyebrow}>APP CABALLOS</Text>

        <Text style={styles.title}>Base técnica preparada</Text>

        <Text style={styles.description}>
          Los flujos de identidad y producto de Architecture 2.1 se
          implementarán en las próximas fases.
        </Text>

        <View style={styles.statusCard}>
          <Text style={styles.statusTitle}>Estado de autenticación</Text>

          <Text style={styles.statusText}>
            {session
              ? 'Sesión de Supabase Auth restaurada.'
              : 'No hay una sesión de Supabase Auth activa.'}
          </Text>
        </View>

        {session ? (
          <Pressable
            accessibilityRole="button"
            disabled={isSigningOut}
            onPress={handleSignOut}
            style={({ pressed }) => [
              styles.button,
              pressed && styles.buttonPressed,
              isSigningOut && styles.buttonDisabled,
            ]}
          >
            {isSigningOut ? (
              <ActivityIndicator color="#fff" />
            ) : (
              <Text style={styles.buttonText}>Cerrar sesión</Text>
            )}
          </Pressable>
        ) : null}
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
    marginBottom: 12,
    color: '#111',
    fontSize: 30,
    fontWeight: '700',
  },
  description: {
    color: '#555',
    fontSize: 16,
    lineHeight: 24,
  },
  statusCard: {
    marginTop: 28,
    padding: 16,
    borderColor: '#ddd',
    borderRadius: 10,
    borderWidth: 1,
    backgroundColor: '#fff',
  },
  statusTitle: {
    marginBottom: 6,
    color: '#111',
    fontSize: 15,
    fontWeight: '600',
  },
  statusText: {
    color: '#666',
    fontSize: 14,
    lineHeight: 20,
  },
  button: {
    minHeight: 50,
    marginTop: 20,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
    backgroundColor: '#111',
  },
  buttonPressed: {
    opacity: 0.8,
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
});