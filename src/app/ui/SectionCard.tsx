import type { ReactNode } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { colors } from './theme';

type Props = {
  title?: string;
  children: ReactNode;
};

export function SectionCard({ title, children }: Props) {
  return (
    <View style={styles.card}>
      {title ? <Text style={styles.title}>{title}</Text> : null}
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    marginBottom: 16,
    padding: 18,
    borderColor: colors.border,
    borderRadius: 10,
    borderWidth: 1,
    backgroundColor: colors.surface,
  },
  title: {
    marginBottom: 12,
    color: colors.text,
    fontSize: 17,
    fontWeight: '700',
  },
});
