import { useState } from 'react';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
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

import type { PublicStackParamList } from '../app/navigation/types';
import {
  logAuthFailure,
  userFacingAuthMessage,
} from '../features/auth/authErrors';
import { requestPasswordReset } from '../features/auth/authService';

type Props = NativeStackScreenProps<PublicStackParamList, 'ForgotPassword'>;

export default function ForgotPasswordScreen({ navigation }: Props) {
  const [email, setEmail] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function handleSubmit() {
    if (!email.trim()) {
      setMessage('Introduce el correo electrónico de la cuenta.');
      return;
    }

    setIsSubmitting(true);
    setMessage(null);

    try {
      const { error } = await requestPasswordReset(email);

      if (error) {
        logAuthFailure('recover', error);
        setMessage(userFacingAuthMessage('recover', error));
        return;
      }

      setMessage(
        'Si existe una cuenta con ese correo, te hemos enviado un enlace para restablecer la contraseña. Revisa también el spam.',
      );
    } catch (error) {
      logAuthFailure('recover', error);
      setMessage(userFacingAuthMessage('recover', error));
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
        <Text style={styles.title}>Restablecer contraseña</Text>
        <Text style={styles.description}>
          Introduce tu correo y te enviaremos un enlace para elegir una
          contraseña nueva.
        </Text>

        <View style={styles.form}>
          <Text style={styles.label}>Correo electrónico</Text>
          <TextInput
            autoCapitalize="none"
            autoComplete="email"
            editable={!isSubmitting}
            keyboardType="email-address"
            onChangeText={setEmail}
            placeholder="nombre@ejemplo.com"
            style={styles.input}
            value={email}
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
                <Text style={styles.primaryButtonText}>Enviar enlace</Text>
              </Pressable>

              <Pressable
                accessibilityRole="button"
                onPress={() => navigation.navigate('Auth')}
                style={({ pressed }) => [
                  styles.linkButton,
                  pressed && styles.buttonPressed,
                ]}
              >
                <Text style={styles.linkButtonText}>Volver al acceso</Text>
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
