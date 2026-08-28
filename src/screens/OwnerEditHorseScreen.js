import React, { useState } from 'react';
import { View, Text, TextInput, TouchableOpacity, StyleSheet, ScrollView, Alert, ActivityIndicator, Image } from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import { supabase } from '../../supabase';

export default function OwnerEditHorseScreen({ route, navigation }) {
  const { horse } = route.params;

  const [name, setName] = useState(horse.name || '');
  const [discipline, setDiscipline] = useState(horse.discipline || '');
  const [levelRequired, setLevelRequired] = useState(horse.level_required ? horse.level_required.toString() : '');
  const [pricePerSession, setPricePerSession] = useState(horse.price_per_session ? horse.price_per_session.toString() : '');
  const [maxDailySessions, setMaxDailySessions] = useState(horse.max_daily_sessions ? horse.max_daily_sessions.toString() : '2');
  const [facilityFee, setFacilityFee] = useState(horse.facility_fee ? horse.facility_fee.toString() : '0');
  
  const [imageUri, setImageUri] = useState(horse.media_url || null);
  const [loading, setLoading] = useState(false);

  async function pickImage() {
    let result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true,
      aspect: [4, 3],
      quality: 0.8,
    });

    if (!result.canceled) {
      setImageUri(result.assets[0].uri);
    }
  }

  async function uploadImageToSupabase(uri) {
    // Si la URI ya es una URL web existente en Supabase, no la subimos de nuevo
    if (uri.startsWith('http')) return uri;

    try {
      const fileExt = uri.split('.').pop().toLowerCase();
      const fileName = `${Date.now()}.${fileExt}`;
      const filePath = `${fileName}`;

      const formData = new FormData();
      formData.append('', {
        uri: uri,
        name: fileName,
        type: `image/${fileExt === 'jpg' ? 'jpeg' : fileExt}`
      });

      const supabaseUrl = supabase.supabaseUrl;
      const res = await fetch(`${supabaseUrl}/storage/v1/object/horse-images/${filePath}`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${(await supabase.auth.getSession())?.data?.session?.access_token}`,
        },
        body: formData,
      });

      if (!res.ok) {
        Alert.alert('Error', 'No se pudo subir la nueva imagen.');
        return null;
      }

      const { data: publicData } = supabase.storage
        .from('horse-images')
        .getPublicUrl(filePath);

      return publicData.publicUrl;
    } catch (error) {
      console.error('Error subiendo imagen:', error);
      return null;
    }
  }

  async function handleUpdateHorse() {
    if (!name || !pricePerSession || !levelRequired) {
      Alert.alert('Error', 'Por favor, rellena los campos obligatorios.');
      return;
    }

    setLoading(true);

    let mediaUrl = imageUri;
    if (imageUri && !imageUri.startsWith('http')) {
      mediaUrl = await uploadImageToSupabase(imageUri);
    }

    const { error } = await supabase
      .from('horses')
      .update({
        name,
        discipline,
        level_required: parseInt(levelRequired),
        price_per_session: parseFloat(pricePerSession),
        max_daily_sessions: parseInt(maxDailySessions),
        facility_fee: parseFloat(facilityFee) || 0,
        media_url: mediaUrl
      })
      .eq('id', horse.id);

    setLoading(false);

    if (error) {
      Alert.alert('Error al actualizar', error.message);
    } else {
      Alert.alert('¡Éxito!', 'Caballo actualizado correctamente.', [
        { text: 'OK', onPress: () => navigation.goBack() }
      ]);
    }
  }

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text style={styles.title}>Editar Caballo</Text>
      <Text style={styles.subtitle}>Modifica los datos y la configuración del animal</Text>

      <Text style={styles.label}>Nombre del Caballo *</Text>
      <TextInput style={styles.input} value={name} onChangeText={setName} />

      <Text style={styles.label}>Disciplina</Text>
      <TextInput style={styles.input} value={discipline} onChangeText={setDiscipline} />

      <Text style={styles.label}>Nivel de Galope Requerido *</Text>
      <TextInput style={styles.input} keyboardType="numeric" value={levelRequired} onChangeText={setLevelRequired} />

      <Text style={styles.label}>Precio por Sesión (€) *</Text>
      <TextInput style={styles.input} keyboardType="numeric" value={pricePerSession} onChangeText={setPricePerSession} />

      <Text style={styles.label}>Máximo de sesiones diarias (Bienestar)</Text>
      <TextInput style={styles.input} keyboardType="numeric" value={maxDailySessions} onChangeText={setMaxDailySessions} />

      <Text style={styles.label}>Canon de Pista de la Hípica (€)</Text>
      <TextInput style={styles.input} keyboardType="numeric" value={facilityFee} onChangeText={setFacilityFee} />

      <Text style={styles.label}>Foto del Caballo</Text>
      <TouchableOpacity style={styles.imagePickerButton} onPress={pickImage}>
        <Text style={styles.imagePickerButtonText}>📷 Cambiar foto</Text>
      </TouchableOpacity>

      {imageUri && (
        <View style={styles.previewContainer}>
          <Image source={{ uri: imageUri }} style={styles.previewImage} />
        </View>
      )}

      {loading ? (
        <ActivityIndicator size="large" color="#111" style={{ marginTop: 20 }} />
      ) : (
        <TouchableOpacity style={styles.button} onPress={handleUpdateHorse}>
          <Text style={styles.buttonText}>Guardar Cambios</Text>
        </TouchableOpacity>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { padding: 24, backgroundColor: '#fff', flexGrow: 1 },
  title: { fontSize: 24, fontWeight: 'bold', color: '#111', marginBottom: 4 },
  subtitle: { fontSize: 14, color: '#666', marginBottom: 24 },
  label: { fontSize: 14, fontWeight: '600', color: '#333', marginBottom: 6, marginTop: 12 },
  input: { backgroundColor: '#f9f9f9', borderWidth: 1, borderColor: '#ddd', padding: 14, borderRadius: 8, fontSize: 16 },
  imagePickerButton: { backgroundColor: '#f0f0f0', borderWidth: 1, borderColor: '#ccc', padding: 14, borderRadius: 8, alignItems: 'center', borderStyle: 'dashed' },
  imagePickerButtonText: { fontSize: 14, fontWeight: '600', color: '#333' },
  previewContainer: { marginTop: 12, alignItems: 'center', width: '100%' },
  previewImage: { width: '100%', height: 200, borderRadius: 8, resizeMode: 'cover' },
  button: { backgroundColor: '#111', padding: 18, borderRadius: 8, alignItems: 'center', marginTop: 32 },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: 'bold' }
});