import { useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
} from 'react-native';

import { signOut } from '../features/auth/authService';
import { DateOfBirthField } from '../features/identity/DateOfBirthField';
import { useIdentity } from '../features/identity/useIdentity';
import {
  isValidDateOfBirth,
  isValidIdentityName,
} from '../features/identity/validation';

export default function IdentityOnboardingScreen() {
  const { identity, completeIdentity } = useIdentity();
  const [firstName, setFirstName] = useState(identity?.firstName ?? '');
  const [lastName, setLastName] = useState(identity?.lastName ?? '');
  const [dateOfBirth, setDateOfBirth] = useState(
    identity?.dateOfBirth ?? '',
  );
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function handleSubmit() {
    if (!isValidIdentityName(firstName) || !isValidIdentityName(lastName)) {
      setMessage('Introduce tu nombre y apellidos.');
      return;
    }

    if (!isValidDateOfBirth(dateOfBirth)) {
      setMessage('Introduce una fecha de nacimiento válida.');
      return;
    }

    setIsSubmitting(true);
    setMessage(null);

    try {
      await completeIdentity({
        firstName,
        lastName,
        dateOfBirth,
      });
    } catch {
      setMessage(
        'No se pudo guardar tu identidad. Inténtalo de nuevo en unos instantes.',
      );
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <SafeAreaView style={styles.container}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        style={styles.container}
      >
        <ScrollView
          contentContainerStyle={styles.content}
          keyboardShouldPersistTaps="handled"
        >
          <Text style={styles.eyebrow}>IDENTIDAD</Text>
          <Text style={styles.title}>Completa tu perfil</Text>
          <Text style={styles.description}>
            Estos datos identifican a la persona asociada a tu cuenta.
          </Text>

          <Text style={styles.label}>Nombre</Text>
          <TextInput
            autoCapitalize="words"
            autoComplete="given-name"
            editable={!isSubmitting}
            onChangeText={setFirstName}
            placeholder="Nombre"
            style={styles.input}
            value={firstName}
          />

          <Text style={styles.label}>Apellidos</Text>
          <TextInput
            autoCapitalize="words"
            autoComplete="family-name"
            editable={!isSubmitting}
            onChangeText={setLastName}
            placeholder="Apellidos"
            style={styles.input}
            value={lastName}
          />

          <Text style={styles.label}>Fecha de nacimiento</Text>
          <DateOfBirthField
            editable={!isSubmitting}
            onChange={setDateOfBirth}
            value={dateOfBirth}
          />

          {message ? (
            <Text accessibilityRole="alert" style={styles.message}>
              {message}
            </Text>
          ) : null}

          <Pressable
            accessibilityRole="button"
            disabled={isSubmitting}
            onPress={handleSubmit}
            style={({ pressed }) => [
              styles.primaryButton,
              pressed && styles.buttonPressed,
              isSubmitting && styles.buttonDisabled,
            ]}
          >
            {isSubmitting ? (
              <ActivityIndicator color="#fff" />
            ) : (
              <Text style={styles.primaryButtonText}>Guardar y continuar</Text>
            )}
          </Pressable>

          <Pressable
            accessibilityRole="button"
            disabled={isSubmitting}
            onPress={signOut}
            style={({ pressed }) => [
              styles.secondaryButton,
              pressed && styles.buttonPressed,
            ]}
          >
            <Text style={styles.secondaryButtonText}>Cerrar sesión</Text>
          </Pressable>
        </ScrollView>
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
    flexGrow: 1,
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
    fontSize: 30,
    fontWeight: '700',
  },
  description: {
    marginTop: 8,
    marginBottom: 28,
    color: '#555',
    fontSize: 16,
    lineHeight: 23,
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
    color: '#9d1c1c',
    fontSize: 14,
    lineHeight: 20,
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
  },
  buttonPressed: {
    opacity: 0.8,
  },
  buttonDisabled: {
    opacity: 0.6,
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
