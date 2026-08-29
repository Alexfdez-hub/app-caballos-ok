import React, { useEffect, useState } from 'react';
import { View, Text, FlatList, StyleSheet, ActivityIndicator, RefreshControl, TouchableOpacity, Image } from 'react-native';
import { supabase } from '../services/supabase/client';

export default function SearchScreen({ navigation }) {
  const [horses, setHorses] = useState([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [currentUser, setCurrentUser] = useState(null);

  useEffect(() => {
    fetchUserDataAndHorses();
  }, []);

  async function fetchUserDataAndHorses() {
    const { data: { user } } = await supabase.auth.getUser();
    setCurrentUser(user);

    // Opcional: Si quieres que el propietario NO vea sus propios caballos en el buscador
    let query = supabase.from('horses').select('*');
    if (user) {
      query = query.neq('owner_id', user.id); // Excluye los caballos del propio dueño logueado
    }

    const { data, error } = await query;
    if (!error && data) {
      setHorses(data);
    }
    setLoading(false);
  }

  async function onRefresh() {
    setRefreshing(true);
    await fetchUserDataAndHorses();
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
        data={horses}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.listContainer}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} colors={['#111']} tintColor="#111" />
        }
        ListEmptyComponent={
          <View style={styles.emptyState}>
            <Text style={styles.emptyText}>No hay caballos disponibles de otros propietarios en este momento.</Text>
          </View>
        }
        renderItem={({ item }) => (
          <TouchableOpacity 
            style={styles.card}
            onPress={() => navigation.navigate('HorseDetail', { horse: item })}
          >
            {item.media_url ? (
              <Image source={{ uri: item.media_url }} style={styles.cardImage} />
            ) : (
              <View style={styles.cardImagePlaceholder}>
                <Text style={styles.placeholderText}>Sin imagen</Text>
              </View>
            )}
            <View style={styles.cardContent}>
              <Text style={styles.cardTitle}>{item.name}</Text>
              <Text style={styles.cardDetail}>Disciplina: {item.discipline || 'General'}</Text>
              <Text style={styles.cardPrice}>{item.price_per_session}€ / sesión</Text>
            </View>
          </TouchableOpacity>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  container: { flex: 1, backgroundColor: '#f5f5f5' },
  listContainer: { padding: 16, gap: 16 },
  emptyState: { padding: 24, alignItems: 'center' },
  emptyText: { color: '#666', fontSize: 16, textAlign: 'center' },
  card: { backgroundColor: '#fff', borderRadius: 12, overflow: 'hidden', elevation: 2, shadowColor: '#000', shadowOpacity: 0.1, shadowRadius: 4, shadowOffset: { width: 0, height: 2 } },
  cardImage: { width: '100%', height: 160 },
  cardImagePlaceholder: { width: '100%', height: 160, backgroundColor: '#e0e0e0', justifyContent: 'center', alignItems: 'center' },
  placeholderText: { color: '#888' },
  cardContent: { padding: 16 },
  cardTitle: { fontSize: 20, fontWeight: 'bold', color: '#111', marginBottom: 4 },
  cardDetail: { fontSize: 14, color: '#666', marginBottom: 8 },
  cardPrice: { fontSize: 16, fontWeight: '600', color: '#2ecc71' }
});