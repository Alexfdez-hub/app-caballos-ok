import React, { useEffect, useState, useCallback } from 'react';
import { View, Text, FlatList, StyleSheet, ActivityIndicator, TouchableOpacity, Image, Alert, RefreshControl } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { supabase } from '../services/supabase/client';

export default function OwnerHorsesScreen({ navigation }) {
  const [horses, setHorses] = useState([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  // useFocusEffect recarga la lista cada vez que el propietario vuelve a esta pantalla
  useFocusEffect(
    useCallback(() => {
      fetchOwnerHorses();
    }, [])
  );

  async function fetchOwnerHorses() {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    const { data, error } = await supabase
      .from('horses')
      .select('*')
      .eq('owner_id', user.id);

    if (!error && data) {
      setHorses(data);
    }
    setLoading(false);
    setRefreshing(false);
  }

  async function handleDelete(horseId) {
    Alert.alert(
      'Eliminar Caballo',
      '¿Estás seguro de que quieres dar de baja este caballo?',
      [
        { text: 'Cancelar', style: 'cancel' },
        { 
          text: 'Eliminar', 
          style: 'destructive', 
          onPress: async () => {
            const { error } = await supabase.from('horses').delete().eq('id', horseId);
            if (error) {
              Alert.alert('Error', error.message);
            } else {
              fetchOwnerHorses();
            }
          } 
        }
      ]
    );
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
          <RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); fetchOwnerHorses(); }} colors={['#111']} />
        }
        ListEmptyComponent={
          <View style={styles.emptyState}>
            <Text style={styles.emptyText}>Aún no has registrado ningún caballo.</Text>
          </View>
        }
        renderItem={({ item }) => (
          <View style={styles.card}>
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
              <Text style={styles.cardDetail}>Nivel Galope: {item.level_required} | Límite diario: {item.max_daily_sessions} sesiones</Text>
              <Text style={styles.cardPrice}>{item.price_per_session}€ / sesión</Text>

              <View style={styles.buttonRow}>
                <TouchableOpacity 
                  style={styles.editButton} 
                  onPress={() => navigation.navigate('OwnerEditHorse', { horse: item })}
                >
                  <Text style={styles.editButtonText}>Editar</Text>
                </TouchableOpacity>

                <TouchableOpacity 
                  style={styles.deleteButton} 
                  onPress={() => handleDelete(item.id)}
                >
                  <Text style={styles.deleteButtonText}>Dar de baja</Text>
                </TouchableOpacity>
              </View>
            </View>
          </View>
        )}
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
  card: { backgroundColor: '#fff', borderRadius: 12, overflow: 'hidden', elevation: 2, shadowColor: '#000', shadowOpacity: 0.1, shadowRadius: 4, shadowOffset: { width: 0, height: 2 } },
  cardImage: { width: '100%', height: 150 },
  cardImagePlaceholder: { width: '100%', height: 150, backgroundColor: '#e0e0e0', justifyContent: 'center', alignItems: 'center' },
  placeholderText: { color: '#888' },
  cardContent: { padding: 16 },
  cardTitle: { fontSize: 20, fontWeight: 'bold', color: '#111', marginBottom: 4 },
  cardDetail: { fontSize: 13, color: '#666', marginBottom: 2 },
  cardPrice: { fontSize: 16, fontWeight: '600', color: '#2ecc71', marginVertical: 8 },
  buttonRow: { flexDirection: 'row', justifyContent: 'flex-end', marginTop: 8 },
  editButton: { backgroundColor: '#007AFF', paddingHorizontal: 12, paddingVertical: 8, borderRadius: 6, marginRight: 8 },
  editButtonText: { color: '#fff', fontSize: 13, fontWeight: 'bold' },
  deleteButton: { backgroundColor: '#ff3b30', paddingHorizontal: 12, paddingVertical: 8, borderRadius: 6 },
  deleteButtonText: { color: '#fff', fontSize: 13, fontWeight: 'bold' }
});