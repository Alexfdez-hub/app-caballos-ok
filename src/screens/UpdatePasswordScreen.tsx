import { useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  SafeAreaView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';

import { useAuth } from '../features/auth/useAuth';
import {
  logAuthFailure,
  userFacingAuthMessage,
} from '../features/auth/authErrors';
import { signOut, updatePassword } from '../features/auth/authService';

export default function UpdatePasswordScreen() {
  const { completePasswordRecovery } = useAuth();
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function handleSubmit() {
    if (password.length < 6) {
      setMessage('La contraseña debe tener al menos 6 caracteres.');
      return;
    }

    if (password !== confirmPassword) {
      setMessage('Las contraseñas no coinciden.');
      return;
    }

    setIsSubmitting(true);
    setMessage(null);

    try {
      const { error } = await updatePassword(password);

      if (error) {
        logAuthFailure('updatePassword', error);
        setMessage(userFacingAuthMessage('updatePassword', error));
        return;
      }

      completePasswordRecovery();
    } catch (error) {
      logAuthFailure('updatePassword', error);
      setMessage(userFacingAuthMessage('updatePassword', error));
    } finally {
      setIsSubmitting(false);
    }
  }

  async function handleCancel() {
    setIsSubmitting(true);
    try {
      await signOut();
      completePasswordRecovery();
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <SafeAreaView style={styles.container}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        style={styles.content}
      >
        <Text style={styles.eyebrow}>ACCESO</Text>
        <Text style={styles.title}>Nueva contraseña</Text>
        <Text style={styles.description}>
          Elige una contraseña nueva para tu cuenta. Después continuarás con
          la sesión iniciada.
        </Text>

        <View style={styles.form}>
          <Text style={styles.label}>Nueva contraseña</Text>
          <TextInput
            autoCapitalize="none"
            autoComplete="new-password"
            editable={!isSubmitting}
            onChangeText={setPassword}
            placeholder="Nueva contraseña"
            secureTextEntry
            style={styles.input}
            value={password}
          />

          <Text style={styles.label}>Repite la contraseña</Text>
          <TextInput
            autoCapitalize="none"
            autoComplete="new-password"
            editable={!isSubmitting}
            onChangeText={setConfirmPassword}
            placeholder="Repite la contraseña"
            secureTextEntry
            style={styles.input}
            value={confirmPassword}
          />

          {message ? (
            <Text accessibilityRole="alert" style={styles.message}>
              {message}
            </Text>
          ) : null}

          {isSubmitting ? (
            <ActivityIndicator color="#111" style={styles.loader} />
          ) : (
            <>
              <Pressable
                accessibilityRole="button"
                onPress={handleSubmit}
                style={({ pressed }) => [
                  styles.primaryButton,
                  pressed && styles.buttonPressed,
                ]}
              >
                <Text style={styles.primaryButtonText}>
                  Guardar contraseña
                </Text>
              </Pressable>

              <Pressable
                accessibilityRole="button"
                onPress={handleCancel}
                style={({ pressed }) => [
                  styles.linkButton,
                  pressed && styles.buttonPressed,
                ]}
              >
                <Text style={styles.linkButtonText}>Cancelar</Text>
              </Pressable>
            </>
          )}
        </View>
      </KeyboardAvoidingView>
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
    fontSize: 32,
    fontWeight: '700',
  },
  description: {
    marginTop: 8,
    color: '#555',
    fontSize: 16,
    lineHeight: 23,
  },
  form: {
    marginTop: 28,
  },
  label: {
    marginBottom: 6,
    color: '#333',
    fontSize: 14,
    fontWeight: '600',
  },
  input: {
    minHeight: 50,
    marginBottom: 16,
    paddingHorizontal: 14,
    borderColor: '#d5d5d5',
    borderRadius: 8,
    borderWidth: 1,
    backgroundColor: '#fff',
    fontSize: 16,
  },
  message: {
    marginBottom: 16,
    color: '#444',
    fontSize: 14,
    lineHeight: 20,
  },
  loader: {
    marginTop: 12,
  },
  primaryButton: {
    minHeight: 50,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
    backgroundColor: '#111',
  },
  linkButton: {
    minHeight: 44,
    marginTop: 8,
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
  linkButtonText: {
    color: '#333',
    fontSize: 15,
    fontWeight: '600',
  },
});
