import React, { useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, SafeAreaView, ActivityIndicator, Alert, Platform, Image, ScrollView } from 'react-native';
import DateTimePicker from '@react-native-community/datetimepicker';
import { supabase } from '../services/supabase/client';

export default function HorseDetailScreen({ route, navigation }) {
  const { horse } = route.params;
  const [loading, setLoading] = useState(false);
  
  const [date, setDate] = useState(new Date());
  const [showPicker, setShowPicker] = useState(false);
  const [mode, setMode] = useState('date');

  const onChange = (event, selectedDate) => {
    const currentDate = selectedDate || date;
    setShowPicker(Platform.OS === 'ios');
    setDate(currentDate);
  };

  const showMode = (currentMode) => {
    setShowPicker(true);
    setMode(currentMode);
  };

  async function handleBooking() {
    setLoading(true);
    
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    
    if (userError || !user) {
      Alert.alert('Error', 'Debes iniciar sesión para reservar.');
      setLoading(false);
      return;
    }

    const { error } = await supabase.from('bookings').insert([
      {
        horse_id: horse.id,
        rider_id: user.id,
        session_date: date.toISOString(),
        status: 'pendiente'
      }
    ]);

    setLoading(false);

    if (error) {
      Alert.alert('Error al reservar', error.message);
    } else {
      Alert.alert(
        '¡Reserva Solicitada!', 
        `Has reservado para el ${date.toLocaleDateString()} a las ${date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`,
        [{ text: 'OK', onPress: () => navigation.goBack() }]
      );
    }
  }

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView contentContainerStyle={styles.scrollContent}>
        <View style={styles.header}>
          {horse.media_url ? (
            <Image source={{ uri: horse.media_url }} style={styles.imageHeader} />
          ) : (
            <View style={styles.imagePlaceholder}>
              <Text style={styles.imageText}>Sin foto de {horse.name}</Text>
            </View>
          )}
        </View>

        <View style={styles.content}>
          <View style={styles.titleRow}>
            <Text style={styles.title}>{horse.name}</Text>
            <Text style={styles.price}>{horse.price_per_session}€ / sesión</Text>
          </View>

          <Text style={styles.label}>Nivel de Galope requerido:</Text>
          <Text style={styles.value}>Nivel {horse.level_required}</Text>

          <Text style={styles.label}>Disciplina:</Text>
          <Text style={styles.value}>{horse.discipline || 'General'}</Text>

          {horse.facility_fee > 0 && (
            <>
              <Text style={styles.label}>Canon de Pista (Hípica):</Text>
              <Text style={styles.value}>{horse.facility_fee}€</Text>
            </>
          )}

          <View style={styles.divider} />

          <Text style={styles.descriptionTitle}>Selecciona Fecha y Hora</Text>
          
          <View style={styles.pickerButtonsRow}>
            <TouchableOpacity style={styles.dateButton} onPress={() => showMode('date')}>
              <Text style={styles.dateButtonText}>📅 {date.toLocaleDateString()}</Text>
            </TouchableOpacity>

            <TouchableOpacity style={styles.dateButton} onPress={() => showMode('time')}>
              <Text style={styles.dateButtonText}>⏰ {date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</Text>
            </TouchableOpacity>
          </View>

          {showPicker && (
            <DateTimePicker
              testID="dateTimePicker"
              value={date}
              mode={mode}
              is24Hour={true}
              display="default"
              onChange={onChange}
              minimumDate={new Date()}
            />
          )}
        </View>
      </ScrollView>

      <View style={styles.footer}>
        {loading ? (
          <ActivityIndicator size="large" color="#111" />
        ) : (
          <TouchableOpacity style={styles.bookButton} onPress={handleBooking}>
            <Text style={styles.bookButtonText}>Confirmar y Reservar</Text>
          </TouchableOpacity>
        )}
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff' },
  scrollContent: { paddingBottom: 24 },
  header: { height: 250, backgroundColor: '#ddd' },
  imageHeader: { width: '100%', height: '100%' },
  imagePlaceholder: { height: '100%', justifyContent: 'center', alignItems: 'center' },
  imageText: { color: '#666', fontSize: 16 },
  content: { padding: 24 },
  titleRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 },
  title: { fontSize: 28, fontWeight: 'bold', color: '#111' },
  price: { fontSize: 18, fontWeight: 'bold', color: '#2ecc71' },
  label: { fontSize: 13, color: '#666', marginTop: 8 },
  value: { fontSize: 16, color: '#111', fontWeight: '500', marginBottom: 4 },
  divider: { height: 1, backgroundColor: '#eee', marginVertical: 16 },
  descriptionTitle: { fontSize: 16, fontWeight: 'bold', color: '#111', marginBottom: 12 },
  pickerButtonsRow: { flexDirection: 'row', gap: 12, marginBottom: 12 },
  dateButton: { flex: 1, backgroundColor: '#f0f0f0', padding: 14, borderRadius: 8, alignItems: 'center', borderWidth: 1, borderColor: '#ddd' },
  dateButtonText: { fontSize: 15, fontWeight: '600', color: '#333' },
  footer: { padding: 24, borderTopWidth: 1, borderColor: '#eee', backgroundColor: '#fff' },
  bookButton: { backgroundColor: '#111', padding: 18, borderRadius: 12, alignItems: 'center' },
  bookButtonText: { color: '#fff', fontSize: 18, fontWeight: 'bold' }
});