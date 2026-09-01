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
  getAuthErrorCode,
  getAuthErrorMessage,
} from '../features/auth/authErrors';
import {
  classifySignUpResult,
  resendSignupConfirmation,
  signInWithEmail,
  signUpWithEmail,
} from '../features/auth/authService';

type Props = NativeStackScreenProps<PublicStackParamList, 'Auth'>;

const PENDING_CONFIRMATION_MESSAGE =
  'Confirma tu correo antes de iniciar sesión. Revisa la bandeja de entrada y el spam.';
const EXISTING_ACCOUNT_MESSAGE =
  'Si ya tenías cuenta, inicia sesión o restablece la contraseña.';

export default function AuthScreen({ navigation }: Props) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [pendingEmail, setPendingEmail] = useState<string | null>(null);

  const normalizedEmail = email.trim().toLowerCase();
  const showResend =
    pendingEmail !== null && pendingEmail === normalizedEmail;

  function hasCredentials(requirePasswordLength = false) {
    if (!email.trim() || !password) {
      setMessage('Introduce tu correo electrónico y contraseña.');
      return false;
    }

    if (requirePasswordLength && password.length < 6) {
      setMessage('La contraseña debe tener al menos 6 caracteres.');
      return false;
    }

    return true;
  }

  async function handleSignIn() {
    if (!hasCredentials()) {
      return;
    }

    setIsSubmitting(true);
    setMessage(null);

    try {
      const { error } = await signInWithEmail(email, password);

      if (!error) {
        return;
      }

      logAuthFailure('signIn', error);

      const code = getAuthErrorCode(error);
      const errorMessage = getAuthErrorMessage(error);
      const unconfirmed =
        code === 'email_not_confirmed' ||
        /email not confirmed/i.test(errorMessage);
      if (unconfirmed) {
        setPendingEmail(normalizedEmail);
      }

      setMessage(userFacingAuthMessage('signIn', error));
    } catch (error) {
      logAuthFailure('signIn', error);
      setMessage(userFacingAuthMessage('signIn', error));
    } finally {
      setIsSubmitting(false);
    }
  }

  async function handleSignUp() {
    if (!hasCredentials(true)) {
      return;
    }

    setIsSubmitting(true);
    setMessage(null);

    try {
      const { data, error } = await signUpWithEmail(email, password);

      if (error) {
        logAuthFailure('signUp', error);
        if (getAuthErrorCode(error) === 'user_repeated_signup') {
          setPendingEmail(null);
          setMessage(EXISTING_ACCOUNT_MESSAGE);
          return;
        }
        setMessage(userFacingAuthMessage('signUp', error));
        return;
      }

      const outcome = classifySignUpResult(data, error);
      if (outcome === 'authenticated') {
        return;
      }

      if (outcome === 'existing_email') {
        setPendingEmail(null);
        setMessage(EXISTING_ACCOUNT_MESSAGE);
        return;
      }

      setPendingEmail(normalizedEmail);
      setMessage(PENDING_CONFIRMATION_MESSAGE);
    } catch (error) {
      logAuthFailure('signUp', error);
      setMessage(userFacingAuthMessage('signUp', error));
    } finally {
      setIsSubmitting(false);
    }
  }

  async function handleResendConfirmation() {
    if (!pendingEmail) {
      return;
    }

    setIsSubmitting(true);

    try {
      const { error } = await resendSignupConfirmation(pendingEmail);

      if (error) {
        logAuthFailure('resend', error);
        setMessage(userFacingAuthMessage('resend', error));
      } else {
        setMessage(
          'Si hay una cuenta pendiente de confirmar, te hemos reenviado el correo. Revisa también el spam.',
        );
      }
    } catch (error) {
      logAuthFailure('resend', error);
      setMessage(userFacingAuthMessage('resend', error));
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
        <Text style={styles.eyebrow}>APP CABALLOS</Text>
        <Text style={styles.title}>Acceso</Text>
        <Text style={styles.description}>
          {showResend
            ? 'Confirma tu correo antes de iniciar sesión. Puedes reenviar el mensaje si no te ha llegado.'
            : 'Crea una cuenta o inicia sesión para continuar.'}
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

          <Text style={styles.label}>Contraseña</Text>
          <TextInput
            autoCapitalize="none"
            autoComplete="password"
            editable={!isSubmitting}
            onChangeText={setPassword}
            placeholder="Contraseña"
            secureTextEntry
            style={styles.input}
            value={password}
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
                onPress={handleSignIn}
                style={({ pressed }) => [
                  styles.primaryButton,
                  pressed && styles.buttonPressed,
                ]}
              >
                <Text style={styles.primaryButtonText}>Iniciar sesión</Text>
              </Pressable>

              <Pressable
                accessibilityRole="button"
                onPress={handleSignUp}
                style={({ pressed }) => [
                  styles.secondaryButton,
                  pressed && styles.buttonPressed,
                ]}
              >
                <Text style={styles.secondaryButtonText}>Crear cuenta</Text>
              </Pressable>

              <Pressable
                accessibilityRole="button"
                onPress={() => navigation.navigate('ForgotPassword')}
                style={({ pressed }) => [
                  styles.linkButton,
                  pressed && styles.buttonPressed,
                ]}
              >
                <Text style={styles.linkButtonText}>
                  ¿Has olvidado tu contraseña?
                </Text>
              </Pressable>

              {showResend ? (
                <Pressable
                  accessibilityRole="button"
                  onPress={handleResendConfirmation}
                  style={({ pressed }) => [
                    styles.secondaryButton,
                    pressed && styles.buttonPressed,
                  ]}
                >
                  <Text style={styles.secondaryButtonText}>
                    Reenviar correo de confirmación
                  </Text>
                </Pressable>
              ) : null}
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
  secondaryButton: {
    minHeight: 50,
    marginTop: 12,
    alignItems: 'center',
    justifyContent: 'center',
    borderColor: '#111',
    borderRadius: 8,
    borderWidth: 1,
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
  secondaryButtonText: {
    color: '#111',
    fontSize: 16,
    fontWeight: '600',
  },
  linkButtonText: {
    color: '#333',
    fontSize: 15,
    fontWeight: '600',
  },
});
