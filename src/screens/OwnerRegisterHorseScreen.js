import React, { useState } from 'react';
import { View, Text, TextInput, TouchableOpacity, StyleSheet, ScrollView, Alert, ActivityIndicator, Image } from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import { supabase } from '../../supabase';

export default function OwnerRegisterHorseScreen({ navigation }) {
  const [name, setName] = useState('');
  const [discipline, setDiscipline] = useState('');
  const [levelRequired, setLevelRequired] = useState('');
  const [pricePerSession, setPricePerSession] = useState('');
  const [maxDailySessions, setMaxDailySessions] = useState('2');
  const [facilityFee, setFacilityFee] = useState('0');
  
  const [imageUri, setImageUri] = useState(null);
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
        const errText = await res.text();
        console.error('Error en respuesta de Supabase Storage:', errText);
        Alert.alert('Error', 'No se pudo subir la imagen al servidor.');
        return null;
      }

      const { data: publicData } = supabase.storage
        .from('horse-images')
        .getPublicUrl(filePath);

      return publicData.publicUrl;
    } catch (error) {
      console.error('Error crítico subiendo imagen:', error);
      Alert.alert('Error de Red', 'Fallo de conexión al subir la imagen.');
      return null;
    }
  }

  async function handleRegisterHorse() {
    if (!name || !pricePerSession || !levelRequired) {
      Alert.alert('Error', 'Por favor, rellena los campos obligatorios (Nombre, Nivel y Precio).');
      return;
    }

    setLoading(true);
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
      Alert.alert('Error', 'No se ha encontrado el usuario activo.');
      setLoading(false);
      return;
    }

    let mediaUrl = null;
    if (imageUri) {
      mediaUrl = await uploadImageToSupabase(imageUri);
    }

    const { error } = await supabase.from('horses').insert([
      {
        owner_id: user.id,
        name,
        discipline,
        level_required: parseInt(levelRequired),
        price_per_session: parseFloat(pricePerSession),
        max_daily_sessions: parseInt(maxDailySessions),
        facility_fee: parseFloat(facilityFee) || 0,
        media_url: mediaUrl
      }
    ]);

    setLoading(false);

    if (error) {
      Alert.alert('Error al registrar', error.message);
    } else {
      Alert.alert('¡Éxito!', 'Caballo registrado con su contenido multimedia.', [
        { text: 'OK', onPress: () => navigation.goBack() }
      ]);
    }
  }

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text style={styles.title}>Dar de alta un Caballo</Text>
      <Text style={styles.subtitle}>Configura los datos, bienestar y soporte multimedia</Text>

      <Text style={styles.label}>Nombre del Caballo *</Text>
      <TextInput style={styles.input} placeholder="Ej. Furia" value={name} onChangeText={setName} />

      <Text style={styles.label}>Disciplina</Text>
      <TextInput style={styles.input} placeholder="Ej. Salto, Doma, Paseo" value={discipline} onChangeText={setDiscipline} />

      <Text style={styles.label}>Nivel de Galope Requerido (1 al 4+) *</Text>
      <TextInput style={styles.input} placeholder="Ej. 2" keyboardType="numeric" value={levelRequired} onChangeText={setLevelRequired} />

      <Text style={styles.label}>Precio por Sesión (€) *</Text>
      <TextInput style={styles.input} placeholder="Ej. 25" keyboardType="numeric" value={pricePerSession} onChangeText={setPricePerSession} />

      <Text style={styles.label}>Límite de Bienestar (Máx. sesiones diarias)</Text>
      <TextInput style={styles.input} placeholder="2" keyboardType="numeric" value={maxDailySessions} onChangeText={setMaxDailySessions} />

      <Text style={styles.label}>Canon de Pista de la Hípica (€ extras si aplica)</Text>
      <TextInput style={styles.input} placeholder="0" keyboardType="numeric" value={facilityFee} onChangeText={setFacilityFee} />

      <Text style={styles.label}>Foto del Caballo / Ubicación de Montura</Text>
      <TouchableOpacity style={styles.imagePickerButton} onPress={pickImage}>
        <Text style={styles.imagePickerButtonText}>📷 Seleccionar foto de la galería</Text>
      </TouchableOpacity>

      {imageUri && (
        <View style={styles.previewContainer}>
          <Image source={{ uri: imageUri }} style={styles.previewImage} />
        </View>
      )}

      {loading ? (
        <ActivityIndicator size="large" color="#111" style={{ marginTop: 20 }} />
      ) : (
        <TouchableOpacity style={styles.button} onPress={handleRegisterHorse}>
          <Text style={styles.buttonText}>Guardar Caballo</Text>
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