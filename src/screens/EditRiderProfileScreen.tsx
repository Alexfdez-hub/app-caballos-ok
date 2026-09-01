import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';

import type { EditRiderProfileScreenProps } from '../app/navigation/types';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { colors } from '../app/ui/theme';
import { userFacingRiderMessage } from '../features/riders/riderErrors';
import { useRiderProfile } from '../features/riders/useRiderProfile';
import type { ProfileVisibility } from '../features/riders/types';
import {
  isValidExperienceStartYear,
  isValidRiderBio,
  parseExperienceStartYear,
} from '../features/riders/validation';

function visibilityLabel(value: ProfileVisibility) {
  return value === 'PUBLIC' ? 'Público' : 'Privado';
}

export default function EditRiderProfileScreen({
  navigation,
}: EditRiderProfileScreenProps) {
  const { profile, isLoading, isSaving, errorMessage, refresh, saveProfile } =
    useRiderProfile();
  const [bio, setBio] = useState('');
  const [experienceYear, setExperienceYear] = useState('');
  const [visibility, setVisibility] = useState<ProfileVisibility>('PRIVATE');
  const [message, setMessage] = useState<string | null>(null);
  const [hasHydrated, setHasHydrated] = useState(false);

  useEffect(() => {
    if (isLoading || hasHydrated || errorMessage) {
      return;
    }

    if (profile) {
      setBio(profile.bio ?? '');
      setExperienceYear(profile.experienceStartYear?.toString() ?? '');
      setVisibility(profile.profileVisibility);
    }

    setHasHydrated(true);
  }, [errorMessage, hasHydrated, isLoading, profile]);

  async function handleSubmit() {
    if (!hasHydrated) {
      return;
    }
    if (!isValidRiderBio(bio)) {
      setMessage('La biografía no puede superar 2000 caracteres.');
      return;
    }

    const parsedYear = parseExperienceStartYear(experienceYear);

    if (
      parsedYear !== null &&
      (Number.isNaN(parsedYear) || !isValidExperienceStartYear(parsedYear))
    ) {
      setMessage('Introduce un año de inicio válido o déjalo vacío.');
      return;
    }

    setMessage(null);

    try {
      await saveProfile({
        bio: bio.trim() || null,
        experienceStartYear: parsedYear,
        profileVisibility: visibility,
      });
      navigation.goBack();
    } catch (error) {
      setMessage(userFacingRiderMessage(error));
    }
  }

  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Perfil de jinete"
        subtitle="Datos básicos del pasaporte. No acreditan nivel, cualificación ni autorización."
      />

      {isLoading && !hasHydrated ? (
        <ActivityIndicator color={colors.text} />
      ) : null}

      {!hasHydrated && errorMessage ? (
        <>
          <Text accessibilityRole="alert" style={styles.message}>
            {errorMessage}
          </Text>
          <Pressable
            accessibilityRole="button"
            onPress={() => {
              void refresh();
            }}
            style={({ pressed }) => [
              styles.button,
              pressed && styles.buttonPressed,
            ]}
          >
            <Text style={styles.buttonText}>Reintentar</Text>
          </Pressable>
        </>
      ) : null}

      {hasHydrated ? (
        <>
      <Text style={styles.label}>Biografía</Text>
      <TextInput
        editable={!isSaving}
        multiline
        onChangeText={setBio}
        placeholder="Opcional"
        placeholderTextColor={colors.disabled}
        style={[styles.input, styles.multiline]}
        textAlignVertical="top"
        value={bio}
      />

      <Text style={styles.label}>Año en que empezaste a montar</Text>
      <TextInput
        editable={!isSaving}
        keyboardType="number-pad"
        maxLength={4}
        onChangeText={setExperienceYear}
        placeholder="Opcional"
        placeholderTextColor={colors.disabled}
        style={styles.input}
        value={experienceYear}
      />

      <Text style={styles.label}>Visibilidad</Text>
      <View style={styles.visibilityRow}>
        {(['PRIVATE', 'PUBLIC'] as const).map((option) => {
          const selected = visibility === option;

          return (
            <Pressable
              accessibilityRole="button"
              accessibilityState={{ selected }}
              disabled={isSaving}
              key={option}
              onPress={() => setVisibility(option)}
              style={[
                styles.visibilityOption,
                selected && styles.visibilityOptionSelected,
              ]}
            >
              <Text
                style={[
                  styles.visibilityOptionText,
                  selected && styles.visibilityOptionTextSelected,
                ]}
              >
                {visibilityLabel(option)}
              </Text>
            </Pressable>
          );
        })}
      </View>
      <Text style={styles.hint}>
        Público guarda una intención. Todavía no hay un directorio público ni
        lectura de otros perfiles.
      </Text>

      {message || errorMessage ? (
        <Text accessibilityRole="alert" style={styles.message}>
          {message || errorMessage}
        </Text>
      ) : null}

      <Pressable
        accessibilityRole="button"
        disabled={isSaving}
        onPress={() => {
          void handleSubmit();
        }}
        style={({ pressed }) => [
          styles.button,
          pressed && styles.buttonPressed,
          isSaving && styles.buttonDisabled,
        ]}
      >
        {isSaving ? (
          <ActivityIndicator color={colors.surface} />
        ) : (
          <Text style={styles.buttonText}>Guardar perfil</Text>
        )}
      </Pressable>
        </>
      ) : null}
    </ScreenScaffold>
  );
}

const styles = StyleSheet.create({
  label: {
    marginBottom: 6,
    color: colors.text,
    fontSize: 14,
    fontWeight: '600',
  },
  input: {
    minHeight: 50,
    marginBottom: 16,
    paddingHorizontal: 14,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: 1,
    backgroundColor: colors.surface,
    color: colors.text,
    fontSize: 16,
  },
  multiline: {
    minHeight: 120,
    paddingVertical: 12,
  },
  visibilityRow: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 8,
  },
  visibilityOption: {
    flex: 1,
    minHeight: 44,
    alignItems: 'center',
    justifyContent: 'center',
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: 1,
    backgroundColor: colors.surface,
  },
  visibilityOptionSelected: {
    borderColor: colors.text,
    backgroundColor: colors.text,
  },
  visibilityOptionText: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '600',
  },
  visibilityOptionTextSelected: {
    color: colors.surface,
  },
  hint: {
    marginBottom: 16,
    color: colors.muted,
    fontSize: 13,
    lineHeight: 18,
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
    backgroundColor: colors.text,
  },
  buttonPressed: {
    opacity: 0.8,
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  buttonText: {
    color: colors.surface,
    fontSize: 16,
    fontWeight: '600',
  },
});
