import Ionicons from '@expo/vector-icons/Ionicons';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { colors } from './theme';

type MenuRowStatus = 'available' | 'comingSoon' | 'empty' | 'readonly';

type Props = {
  label: string;
  description?: string;
  status?: MenuRowStatus;
  isLast?: boolean;
  onPress?: () => void;
};

export function MenuRow({
  label,
  description,
  status = 'available',
  isLast = false,
  onPress,
}: Props) {
  const isInteractive = status === 'available' && onPress !== undefined;
  const trailingLabel =
    status === 'comingSoon'
      ? 'Próximamente'
      : status === 'empty'
        ? 'Sin información'
        : null;

  const content = (
    <>
      <View style={styles.copy}>
        <Text style={styles.label}>{label}</Text>
        {description ? (
          <Text style={styles.description}>{description}</Text>
        ) : null}
      </View>
      {trailingLabel ? (
        <Text style={styles.status}>{trailingLabel}</Text>
      ) : isInteractive ? (
        <Ionicons
          color={colors.faint}
          name="chevron-forward"
          size={18}
        />
      ) : null}
    </>
  );

  const rowStyle = [styles.row, !isLast && styles.separator];

  if (!isInteractive) {
    return <View style={rowStyle}>{content}</View>;
  }

  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => [rowStyle, pressed && styles.pressed]}
    >
      {content}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  row: {
    minHeight: 52,
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
  },
  separator: {
    borderBottomColor: colors.border,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  pressed: {
    opacity: 0.7,
  },
  copy: {
    flex: 1,
    paddingRight: 12,
  },
  label: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '600',
  },
  description: {
    marginTop: 3,
    color: colors.muted,
    fontSize: 13,
    lineHeight: 18,
  },
  status: {
    color: colors.disabled,
    fontSize: 12,
    fontWeight: '600',
  },
});
