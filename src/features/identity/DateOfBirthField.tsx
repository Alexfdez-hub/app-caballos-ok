import { createElement, useState } from 'react';
import {
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import DateTimePicker, {
  type DateTimePickerEvent,
} from '@react-native-community/datetimepicker';

type DateOfBirthFieldProps = {
  value: string;
  onChange: (value: string) => void;
  editable?: boolean;
};

function parseLocalDate(value: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) {
    return null;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const parsed = new Date(year, month - 1, day);

  if (
    parsed.getFullYear() !== year ||
    parsed.getMonth() !== month - 1 ||
    parsed.getDate() !== day
  ) {
    return null;
  }

  return parsed;
}

export function formatDateOfBirth(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function formatDisplayDate(value: string) {
  const parsed = parseLocalDate(value);
  if (!parsed) {
    return value;
  }

  return parsed.toLocaleDateString('es-ES', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  });
}

export function DateOfBirthField({
  value,
  onChange,
  editable = true,
}: DateOfBirthFieldProps) {
  const selected = parseLocalDate(value) ?? new Date(2000, 0, 1);
  const [showPicker, setShowPicker] = useState(false);
  const [pickerDate, setPickerDate] = useState(selected);
  const maximumDate = new Date();

  function openPicker() {
    if (!editable) {
      return;
    }

    setPickerDate(parseLocalDate(value) ?? new Date(2000, 0, 1));
    setShowPicker(true);
  }

  function handleNativeChange(event: DateTimePickerEvent, date?: Date) {
    if (event.type === 'dismissed') {
      setShowPicker(false);
      return;
    }

    if (!date) {
      return;
    }

    if (Platform.OS === 'android') {
      setShowPicker(false);
      onChange(formatDateOfBirth(date));
      return;
    }

    setPickerDate(date);
  }

  if (Platform.OS === 'web') {
    return createElement('input', {
      disabled: !editable,
      max: formatDateOfBirth(maximumDate),
      onChange: (event: { target: { value: string } }) => {
        onChange(event.target.value);
      },
      style: webInputStyle,
      type: 'date',
      value,
    });
  }

  return (
    <View>
      <Pressable
        accessibilityRole="button"
        disabled={!editable}
        onPress={openPicker}
        style={({ pressed }) => [
          styles.input,
          pressed && editable && styles.pressed,
        ]}
      >
        <Text style={value ? styles.value : styles.placeholder}>
          {value ? formatDisplayDate(value) : 'Selecciona una fecha'}
        </Text>
      </Pressable>

      {showPicker ? (
        <View>
          <DateTimePicker
            display={Platform.OS === 'ios' ? 'spinner' : 'default'}
            maximumDate={maximumDate}
            mode="date"
            onChange={handleNativeChange}
            value={pickerDate}
          />
          {Platform.OS === 'ios' ? (
            <Pressable
              accessibilityRole="button"
              onPress={() => {
                onChange(formatDateOfBirth(pickerDate));
                setShowPicker(false);
              }}
              style={({ pressed }) => [
                styles.doneButton,
                pressed && styles.pressed,
              ]}
            >
              <Text style={styles.doneButtonText}>Listo</Text>
            </Pressable>
          ) : null}
        </View>
      ) : null}
    </View>
  );
}

const webInputStyle = {
  minHeight: 50,
  marginBottom: 16,
  paddingLeft: 14,
  paddingRight: 14,
  borderColor: '#d5d5d5',
  borderRadius: 8,
  borderWidth: 1,
  borderStyle: 'solid' as const,
  backgroundColor: '#fff',
  fontSize: 16,
  width: '100%',
  boxSizing: 'border-box' as const,
};

const styles = StyleSheet.create({
  input: {
    minHeight: 50,
    marginBottom: 16,
    justifyContent: 'center',
    paddingHorizontal: 14,
    borderColor: '#d5d5d5',
    borderRadius: 8,
    borderWidth: 1,
    backgroundColor: '#fff',
  },
  value: {
    color: '#111',
    fontSize: 16,
  },
  placeholder: {
    color: '#888',
    fontSize: 16,
  },
  pressed: {
    opacity: 0.8,
  },
  doneButton: {
    minHeight: 44,
    marginBottom: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  doneButtonText: {
    color: '#111',
    fontSize: 16,
    fontWeight: '600',
  },
});
