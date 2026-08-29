import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, StyleSheet, ActivityIndicator, RefreshControl } from 'react-native';
import { supabase } from '../services/supabase/client';

export default function BookingsScreen() {
  const [bookings, setBookings] = useState([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => {
    fetchBookings();
  }, []);

  async function fetchBookings() {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    // Consultamos las reservas del usuario cruzándolas con la tabla de caballos para obtener el nombre
    const { data, error } = await supabase
      .from('bookings')
      .select(`
        id,
        session_date,
        status,
        horses ( name, discipline, price_per_session )
      `)
      .eq('rider_id', user.id);

    if (!error && data) {
      setBookings(data);
    }
    setLoading(false);
  }

  async function onRefresh() {
    setRefreshing(true);
    await fetchBookings();
    setRefreshing(false);
  }

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#111" />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <FlatList
        data={bookings}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.listContainer}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} colors={['#111']} tintColor="#111" />
        }
        ListEmptyComponent={
          <View style={styles.emptyState}>
            <Text style={styles.emptyText}>No tienes ninguna reserva activa en este momento.</Text>
          </View>
        }
        renderItem={({ item }) => {
          const sessionDate = new Date(item.session_date);
          return (
            <View style={styles.card}>
              <View style={styles.cardHeader}>
                <Text style={styles.horseName}>{item.horses?.name || 'Caballo'}</Text>
                <View style={styles.badge}>
                  <Text style={styles.badgeText}>{item.status.toUpperCase()}</Text>
                </View>
              </View>
              <Text style={styles.detail}>Disciplina: {item.horses?.discipline || 'General'}</Text>
              <Text style={styles.date}>
                📅 {sessionDate.toLocaleDateString()} a las {sessionDate.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
              </Text>
              <View style={styles.passIndicator}>
                <Text style={styles.passText}>🎫 Pase de Acceso Digital Válido</Text>
              </View>
            </View>
          );
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  container: { flex: 1, backgroundColor: '#f5f5f5' },
  listContainer: { padding: 16, gap: 16 },
  emptyState: { padding: 32, alignItems: 'center' },
  emptyText: { color: '#666', fontSize: 16, textAlign: 'center' },
  card: { backgroundColor: '#fff', padding: 16, borderRadius: 12, elevation: 2, shadowColor: '#000', shadowOpacity: 0.1, shadowRadius: 4, shadowOffset: { width: 0, height: 2 } },
  cardHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 },
  horseName: { fontSize: 20, fontWeight: 'bold', color: '#111' },
  badge: { backgroundColor: '#e2f0d9', paddingHorizontal: 8, paddingVertical: 4, borderRadius: 6 },
  badgeText: { color: '#385723', fontSize: 12, fontWeight: 'bold' },
  detail: { fontSize: 14, color: '#666', marginBottom: 4 },
  date: { fontSize: 15, fontWeight: '600', color: '#333', marginBottom: 12 },
  passIndicator: { backgroundColor: '#f0f0f0', padding: 8, borderRadius: 6, alignItems: 'center' },
  passText: { fontSize: 13, fontWeight: '600', color: '#444' }
});