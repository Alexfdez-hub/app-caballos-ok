import { StyleSheet, Text, View } from 'react-native';

import { colors } from './theme';

type Props = {
  title: string;
  description: string;
};

export function EmptyStateCard({ title, description }: Props) {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>{title}</Text>
      <Text style={styles.description}>{description}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingVertical: 4,
  },
  title: {
    color: colors.text,
    fontSize: 16,
    fontWeight: '600',
  },
  description: {
    marginTop: 4,
    color: colors.muted,
    fontSize: 14,
    lineHeight: 20,
  },
});
