import { useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';

import type { CreateEquineScreenProps } from '../app/navigation/types';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { colors } from '../app/ui/theme';
import { userFacingEquineCreateMessage } from '../features/equines/equineCreate';
import { createMyEquine } from '../features/equines/equineCreateService';

export default function CreateEquineScreen({
  navigation,
}: CreateEquineScreenProps) {
  const [name, setName] = useState('');
  const [equineType, setEquineType] = useState<'HORSE' | 'PONY'>('HORSE');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function handleSubmit() {
    if (name.trim().length === 0) {
      setMessage('Escribe el nombre del equino.');
      return;
    }

    setIsSubmitting(true);
    setMessage(null);
    try {
      const equineId = await createMyEquine({
        name: name.trim(),
        equineType,
      });
      navigation.replace('EquineDetail', { equineId });
    } catch (error) {
      setMessage(userFacingEquineCreateMessage(error));
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <ScreenScaffold>
      <Text style={styles.label}>Nombre</Text>
      <TextInput
        accessibilityLabel="Nombre del equino"
        autoCapitalize="words"
        onChangeText={setName}
        placeholder="Nombre"
        placeholderTextColor={colors.muted}
        style={styles.input}
        value={name}
      />

      <Text style={styles.label}>Tipo</Text>
      <View style={styles.typeRow}>
        <TypeButton
          label="Caballo"
          selected={equineType === 'HORSE'}
          onPress={() => setEquineType('HORSE')}
        />
        <TypeButton
          label="Poni"
          selected={equineType === 'PONY'}
          onPress={() => setEquineType('PONY')}
        />
      </View>

      {message ? (
        <Text accessibilityRole="alert" style={styles.message}>
          {message}
        </Text>
      ) : null}

      <Pressable
        accessibilityRole="button"
        disabled={isSubmitting}
        onPress={() => {
          void handleSubmit();
        }}
        style={({ pressed }) => [
          styles.primaryButton,
          pressed && styles.buttonPressed,
          isSubmitting && styles.buttonDisabled,
        ]}
      >
        {isSubmitting ? (
          <ActivityIndicator color={colors.surface} />
        ) : (
          <Text style={styles.primaryButtonText}>Crear equino</Text>
        )}
      </Pressable>
    </ScreenScaffold>
  );
}

function TypeButton({
  label,
  selected,
  onPress,
}: {
  label: string;
  selected: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ selected }}
      onPress={onPress}
      style={({ pressed }) => [
        styles.typeButton,
        selected && styles.typeButtonSelected,
        pressed && styles.buttonPressed,
      ]}
    >
      <Text
        style={[styles.typeButtonText, selected && styles.typeButtonTextSelected]}
      >
        {label}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  label: {
    marginBottom: 8,
    color: colors.text,
    fontSize: 14,
    fontWeight: '600',
  },
  input: {
    minHeight: 50,
    marginBottom: 16,
    paddingHorizontal: 14,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.surface,
    color: colors.text,
    fontSize: 16,
  },
  typeRow: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 16,
  },
  typeButton: {
    flex: 1,
    minHeight: 48,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.surface,
  },
  typeButtonSelected: {
    borderColor: colors.text,
    backgroundColor: colors.text,
  },
  typeButtonText: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '600',
  },
  typeButtonTextSelected: {
    color: colors.surface,
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
    backgroundColor: colors.text,
  },
  buttonPressed: {
    opacity: 0.8,
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  primaryButtonText: {
    color: colors.surface,
    fontSize: 16,
    fontWeight: '600',
  },
});
