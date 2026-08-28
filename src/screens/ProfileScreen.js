import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator } from 'react-native';
import { supabase } from '../../supabase';

export default function ProfileScreen({ navigation }) {
  const [userEmail, setUserEmail] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchUserData();
  }, []);

  async function fetchUserData() {
    const { data: { user } } = await supabase.auth.getUser();
    if (user) {
      setUserEmail(user.email);
    }
    setLoading(false);
  }

  async function handleLogout() {
    await supabase.auth.signOut();
    navigation.replace('Login');
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
      <Text style={styles.title}>Mi Perfil</Text>
      <Text style={styles.email}>{userEmail}</Text>

      <View style={styles.section}>
        <TouchableOpacity 
          style={styles.actionButton} 
          onPress={() => navigation.navigate('RegisterHorse')}
        >
          <Text style={styles.actionText}>+ Registrar Nuevo Caballo</Text>
        </TouchableOpacity>

        <TouchableOpacity 
          style={styles.actionButton} 
          onPress={() => navigation.navigate('OwnerHorses')}
        >
          <Text style={styles.actionText}>🐴 Ver y gestionar mis caballos</Text>
        </TouchableOpacity>
      </View>

      <TouchableOpacity style={styles.logoutButton} onPress={handleLogout}>
        <Text style={styles.logoutText}>Cerrar Sesión</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  container: { flex: 1, padding: 24, backgroundColor: '#fff', justifyContent: 'space-between' },
  title: { fontSize: 28, fontWeight: 'bold', color: '#111', marginTop: 20 },
  email: { fontSize: 16, color: '#666', marginBottom: 24 },
  section: { flex: 1, gap: 12 },
  actionButton: { backgroundColor: '#f0f0f0', padding: 16, borderRadius: 8, alignItems: 'center', borderWidth: 1, borderColor: '#ddd' },
  actionText: { fontSize: 16, fontWeight: '600', color: '#111' },
  logoutButton: { backgroundColor: '#ff3b30', padding: 16, borderRadius: 8, alignItems: 'center', marginBottom: 20 },
  logoutText: { color: '#fff', fontSize: 16, fontWeight: 'bold' }
});