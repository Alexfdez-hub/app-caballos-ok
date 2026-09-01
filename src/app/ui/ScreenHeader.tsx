import { StyleSheet, Text, View } from 'react-native';

import { colors } from './theme';

type Props = {
  eyebrow?: string;
  title: string;
  subtitle?: string;
};

export function ScreenHeader({ eyebrow, title, subtitle }: Props) {
  return (
    <View style={styles.container}>
      {eyebrow ? <Text style={styles.eyebrow}>{eyebrow}</Text> : null}
      <Text style={styles.title}>{title}</Text>
      {subtitle ? <Text style={styles.subtitle}>{subtitle}</Text> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    marginBottom: 24,
  },
  eyebrow: {
    marginBottom: 8,
    color: colors.accent,
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 1.5,
  },
  title: {
    color: colors.text,
    fontSize: 30,
    fontWeight: '700',
  },
  subtitle: {
    marginTop: 8,
    color: colors.muted,
    fontSize: 16,
    lineHeight: 23,
  },
});
