import { useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
} from 'react-native';

import type { EditIdentityScreenProps } from '../app/navigation/types';
import { DateOfBirthField } from '../features/identity/DateOfBirthField';
import { useIdentity } from '../features/identity/useIdentity';
import {
  isValidDateOfBirth,
  isValidIdentityName,
} from '../features/identity/validation';

export default function EditIdentityScreen({
  navigation,
}: EditIdentityScreenProps) {
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
      await completeIdentity({ firstName, lastName, dateOfBirth });
      navigation.goBack();
    } catch {
      setMessage(
        'No se pudieron guardar los cambios. Inténtalo de nuevo en unos instantes.',
      );
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView
        contentContainerStyle={styles.content}
        keyboardShouldPersistTaps="handled"
      >
        <Text style={styles.title}>Datos básicos</Text>

        <Text style={styles.label}>Nombre</Text>
        <TextInput
          autoCapitalize="words"
          autoComplete="given-name"
          editable={!isSubmitting}
          onChangeText={setFirstName}
          style={styles.input}
          value={firstName}
        />

        <Text style={styles.label}>Apellidos</Text>
        <TextInput
          autoCapitalize="words"
          autoComplete="family-name"
          editable={!isSubmitting}
          onChangeText={setLastName}
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
            styles.button,
            pressed && styles.buttonPressed,
            isSubmitting && styles.buttonDisabled,
          ]}
        >
          {isSubmitting ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.buttonText}>Guardar cambios</Text>
          )}
        </Pressable>
      </ScrollView>
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
    padding: 24,
  },
  title: {
    marginBottom: 28,
    color: '#111',
    fontSize: 28,
    fontWeight: '700',
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
  },
  button: {
    minHeight: 50,
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
