import { useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';

import type { ExploreScreenProps } from '../app/navigation/types';
import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import { useAuth } from '../features/auth/useAuth';
import { formatOfferRange } from '../features/explore/formatOfferRange';
import { initialExploreRange, shiftExploreRange } from '../features/explore/exploreRange';
import type { BookableOffer } from '../features/explore/types';
import { useBookableOffers } from '../features/explore/useBookableOffers';

export default function ExploreScreen({ navigation }: ExploreScreenProps) {
  const { session } = useAuth();
  const [range, setRange] = useState(() => initialExploreRange(new Date()));
  const { rows, isLoading, errorMessage, refresh } = useBookableOffers(
    session?.user.id ?? null,
    range,
  );

  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Explorar"
        subtitle="Franjas que ya se pueden reservar. No incluye la cesión interna ni los bloqueos."
      />

      <Text style={styles.range}>
        {formatOfferRange(range.start, range.end, 'UTC')}
      </Text>
      <Pressable
        accessibilityRole="button"
        onPress={() => {
          setRange((current) => shiftExploreRange(current, -7));
        }}
        style={styles.secondaryButton}
      >
        <Text style={styles.secondaryButtonText}>Siete días anteriores</Text>
      </Pressable>
      <Pressable
        accessibilityRole="button"
        onPress={() => {
          setRange((current) => shiftExploreRange(current, 7));
        }}
        style={styles.secondaryButton}
      >
        <Text style={styles.secondaryButtonText}>Siete días siguientes</Text>
      </Pressable>

      {isLoading ? <ActivityIndicator color={colors.text} /> : null}
      {errorMessage ? (
        <Text accessibilityRole="alert" style={styles.message}>
          {errorMessage}
        </Text>
      ) : null}

      {!isLoading ? (
        <Pressable
          accessibilityRole="button"
          onPress={() => {
            void refresh();
          }}
          style={styles.primaryButton}
        >
          <Text style={styles.primaryButtonText}>
            {errorMessage ? 'Reintentar' : 'Actualizar'}
          </Text>
        </Pressable>
      ) : null}

      {!isLoading && !errorMessage && rows.length === 0 ? (
        <EmptyStateCard
          title="No hay franjas reservables"
          description="En este intervalo no hay una ventana final reservable. Un equino privado no aparece aquí."
        />
      ) : null}

      {rows.map((offer) => (
        <OfferCard
          key={`${offer.serviceId}-${offer.equineId}-${offer.startsAt}`}
          offer={offer}
          onPress={() => {
            navigation.navigate('BookableOffer', {
              equineId: offer.equineId,
              centerId: offer.centerId,
              serviceId: offer.serviceId,
              startsAt: offer.startsAt,
              endsAt: offer.endsAt,
            });
          }}
        />
      ))}
    </ScreenScaffold>
  );
}

function OfferCard({
  offer,
  onPress,
}: {
  offer: BookableOffer;
  onPress: () => void;
}) {
  return (
    <SectionCard title={offer.centerName}>
      <Text style={styles.equine}>{offer.equineName}</Text>
      <Text style={styles.service}>{offer.serviceName}</Text>
      <Text style={styles.when}>
        {formatOfferRange(offer.startsAt, offer.endsAt, offer.centerTimezone)}
      </Text>
      <Text style={styles.note}>
        {offer.durationLimitMinutes === null
          ? 'No hay un límite de duración aprobado para este equino.'
          : `Límite registrado: ${offer.durationLimitMinutes} min.`}
      </Text>
      <Pressable accessibilityRole="button" onPress={onPress} style={styles.primaryButton}>
        <Text style={styles.primaryButtonText}>Ver franja</Text>
      </Pressable>
    </SectionCard>
  );
}

const styles = StyleSheet.create({
  range: {
    marginBottom: 8,
    color: colors.muted,
    fontSize: 14,
  },
  equine: {
    color: colors.text,
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 4,
  },
  service: {
    color: colors.text,
    fontSize: 16,
    marginBottom: 4,
  },
  when: {
    color: colors.text,
    fontSize: 16,
    marginBottom: 4,
  },
  note: {
    color: colors.muted,
    fontSize: 14,
    lineHeight: 20,
    marginBottom: 8,
  },
  message: {
    marginBottom: 16,
    color: '#9d1c1c',
    fontSize: 14,
    lineHeight: 20,
  },
  primaryButton: {
    minHeight: 48,
    marginBottom: 12,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
    backgroundColor: colors.text,
  },
  primaryButtonText: {
    color: colors.surface,
    fontSize: 16,
    fontWeight: '600',
  },
  secondaryButton: {
    minHeight: 44,
    marginBottom: 8,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.surface,
  },
  secondaryButtonText: {
    color: colors.text,
    fontSize: 15,
  },
});
