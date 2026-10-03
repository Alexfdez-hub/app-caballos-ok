import { useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';

import { listIdentityMarkets } from './identityService';
import { IDENTITY_MARKET_LOAD_ERROR } from './identityMarket';
import type { IdentityMarket } from './types';
import { identityMarketLabel } from './validation';

type IdentityCountryFieldProps = {
  value: string;
  onChange: (countryCode: string) => void;
  editable?: boolean;
};

export function IdentityCountryField({
  value,
  onChange,
  editable = true,
}: IdentityCountryFieldProps) {
  const [markets, setMarkets] = useState<IdentityMarket[] | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let active = true;

    void listIdentityMarkets()
      .then((nextMarkets) => {
        if (active) {
          setMarkets(nextMarkets);
          setFailed(false);
        }
      })
      .catch(() => {
        if (active) {
          setMarkets([]);
          setFailed(true);
        }
      });

    return () => {
      active = false;
    };
  }, []);

  return (
    <View style={styles.group}>
      <Text style={styles.hint}>
        Elige el país de tu perfil. No se deduce del idioma ni del dispositivo.
      </Text>
      {markets === null ? <ActivityIndicator color="#111" /> : null}
      {failed ? (
        <Text accessibilityRole="alert" style={styles.error}>
          {IDENTITY_MARKET_LOAD_ERROR}
        </Text>
      ) : null}
      {markets?.length === 0 && !failed ? (
        <Text style={styles.error}>No hay países disponibles.</Text>
      ) : null}
      {markets?.map((market) => {
        const selected = market.countryCode === value;
        return (
          <Pressable
            accessibilityRole="button"
            accessibilityState={{ selected, disabled: !editable }}
            disabled={!editable}
            key={market.countryCode}
            onPress={() => onChange(market.countryCode)}
            style={[styles.option, selected && styles.optionSelected]}
          >
            <Text style={styles.optionText}>
              {identityMarketLabel(market.countryCode)}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  group: {
    marginBottom: 16,
  },
  hint: {
    marginBottom: 10,
    color: '#555',
    fontSize: 14,
    lineHeight: 20,
  },
  error: {
    marginBottom: 10,
    color: '#9d1c1c',
    fontSize: 14,
    lineHeight: 20,
  },
  option: {
    minHeight: 48,
    justifyContent: 'center',
    marginBottom: 8,
    paddingHorizontal: 14,
    borderColor: '#d5d5d5',
    borderRadius: 8,
    borderWidth: 1,
    backgroundColor: '#fff',
  },
  optionSelected: {
    borderColor: '#111',
    backgroundColor: '#e8efe9',
  },
  optionText: {
    color: '#111',
    fontSize: 16,
  },
});
