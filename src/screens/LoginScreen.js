import React, { useState } from 'react';
import { View, Text, TextInput, TouchableOpacity, StyleSheet, ActivityIndicator, Alert } from 'react-native';
import { supabase } from '../services/supabase/client';

export default function LoginScreen({ navigation }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);

  async function handleLogin() {
    setLoading(true);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    
    if (error) {
      Alert.alert('Error al entrar', error.message);
    } else {
      Alert.alert('¡Bienvenido!', 'Sesión iniciada correctamente');
    }
    
    setLoading(false);
  }

  async function handleRegister() {
    setLoading(true);
    const { data, error } = await supabase.auth.signUp({ email, password });
    if (error) Alert.alert('Error al registrar', error.message);
    else if (data.session) Alert.alert('Cuenta creada', 'Tu cuenta se ha creado y la sesión está iniciada');
    else Alert.alert('Registro exitoso', 'Revisa tu correo para verificar la cuenta');
    setLoading(false);
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Acceso</Text>
      <Text style={styles.subtitle}>Plataforma de Alquiler Ecuestre</Text>

      <TextInput
        style={styles.input}
        placeholder="Correo electrónico"
        autoCapitalize="none"
        keyboardType="email-address"
        value={email}
        onChangeText={setEmail}
      />
      <TextInput
        style={styles.input}
        placeholder="Contraseña"
        secureTextEntry
        value={password}
        onChangeText={setPassword}
      />

      {loading ? (
        <ActivityIndicator size="large" color="#333" style={styles.loader} />
      ) : (
        <View style={styles.buttonContainer}>
          <TouchableOpacity style={styles.primaryButton} onPress={handleLogin}>
            <Text style={styles.primaryButtonText}>Iniciar Sesión</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.secondaryButton} onPress={handleRegister}>
            <Text style={styles.secondaryButtonText}>Crear Cuenta</Text>
          </TouchableOpacity>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f5f5f5', justifyContent: 'center', padding: 24 },
  title: { fontSize: 32, fontWeight: 'bold', color: '#111', marginBottom: 8 },
  subtitle: { fontSize: 16, color: '#666', marginBottom: 32 },
  input: { backgroundColor: '#fff', padding: 16, borderRadius: 8, marginBottom: 16, fontSize: 16, elevation: 1 },
  buttonContainer: { marginTop: 16, gap: 12 },
  primaryButton: { backgroundColor: '#111', padding: 16, borderRadius: 8, alignItems: 'center' },
  primaryButtonText: { color: '#fff', fontSize: 16, fontWeight: 'bold' },
  secondaryButton: { backgroundColor: 'transparent', padding: 16, borderRadius: 8, alignItems: 'center', borderWidth: 1, borderColor: '#111' },
  secondaryButtonText: { color: '#111', fontSize: 16, fontWeight: 'bold' },
  loader: { marginTop: 24 }
});