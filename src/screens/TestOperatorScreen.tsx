import { useCallback, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';

import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { colors } from '../app/ui/theme';
import { listMyEquines } from '../features/equines/equineCreateService';
import {
  addTestBlock,
  assignTestCenterRole,
  assignTestEquine,
  createTestCenter,
  createTestService,
  grantTestPermission,
  linkTestService,
  listTestWorkspace,
  markTestVisibility,
  openTestPilot,
  registerTestEquine,
  retireTestOperatorData,
  setTestAvailability,
  testOperatorErrorMessage,
  transferTestManager,
  transferTestOwnership,
  type TestWorkspaceRow,
} from '../features/testOperator/testOperatorService';

const ROLES = ['ADMIN', 'MANAGER', 'INSTRUCTOR', 'ASSESSOR'] as const;
const PERMISSIONS = [
  'MANAGE_AVAILABILITY',
  'MANAGE_BOOKINGS',
  'MANAGE_REQUIREMENTS',
  'VIEW_ACTIVITY',
] as const;
const BLOCKS = ['REST', 'VET', 'OWNER_USE', 'MANUAL_BLOCK'] as const;

export default function TestOperatorScreen() {
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [workspace, setWorkspace] = useState<TestWorkspaceRow[]>([]);
  const [ownEquines, setOwnEquines] = useState<Array<{ id: string; name: string }>>([]);
  const [centerId, setCenterId] = useState<string | null>(null);
  const [equineId, setEquineId] = useState<string | null>(null);
  const [serviceId, setServiceId] = useState<string | null>(null);
  const [centerName, setCenterName] = useState('TEST_ONLY Centro');
  const [timezone, setTimezone] = useState('Europe/Madrid');
  const [email, setEmail] = useState('');
  const [serviceName, setServiceName] = useState('TEST_ONLY Sesión');
  const [duration, setDuration] = useState('60');
  const [pilotCode, setPilotCode] = useState('TEST_ONLY_FLOW');
  const [startsAt, setStartsAt] = useState('');
  const [endsAt, setEndsAt] = useState('');

  const refresh = useCallback(async () => {
    const [rows, equines] = await Promise.all([listTestWorkspace(), listMyEquines()]);
    setWorkspace(rows);
    setOwnEquines(
      equines
        .filter((equine) => equine.equineName.startsWith('TEST_ONLY ') && equine.isPrimaryManager)
        .map((equine) => ({ id: equine.equineId, name: equine.equineName })),
    );
  }, []);

  async function run(action: () => Promise<unknown>, done: string) {
    setBusy(true);
    setErrorMessage(null);
    setNotice(null);
    try {
      await action();
      await refresh();
      setNotice(done);
    } catch (error) {
      setErrorMessage(testOperatorErrorMessage(error));
    } finally {
      setBusy(false);
    }
  }

  const centers = workspace.filter((row) => row.kind === 'CENTER');
  const equines = workspace.filter((row) => row.kind === 'EQUINE');
  const services = workspace.filter((row) => row.kind === 'SERVICE');

  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Operación de prueba"
        subtitle="Solo en una base local con la compuerta de prueba. Todo nombre empieza por TEST_ONLY. No verifica identidad ni abre el directorio público."
      />
      {busy ? <ActivityIndicator color={colors.text} /> : null}
      {errorMessage ? (
        <Text accessibilityRole="alert" style={styles.error}>
          {errorMessage}
        </Text>
      ) : null}
      {notice ? <Text style={styles.notice}>{notice}</Text> : null}

      <SectionCard title="1. Centro">
        <Field label="Nombre" value={centerName} onChangeText={setCenterName} />
        <Field label="Zona horaria" value={timezone} onChangeText={setTimezone} />
        <Action
          label="Crear centro"
          onPress={() => {
            void run(() => createTestCenter(centerName.trim(), timezone.trim()), 'Centro creado.');
          }}
        />
        {centers.map((row) => (
          <Choice
            key={row.entityId}
            label={row.label}
            selected={centerId === row.entityId}
            onPress={() => setCenterId(row.entityId)}
          />
        ))}
      </SectionCard>

      <SectionCard title="2. Personas del centro">
        <Text style={styles.hint}>
          La otra cuenta ya tiene que existir y haber completado la identidad. El correo es el de acceso.
        </Text>
        <Field label="Correo" value={email} onChangeText={setEmail} />
        <View style={styles.row}>
          {ROLES.map((role) => (
            <Action
              key={role}
              label={role}
              onPress={() => {
                if (!centerId) {
                  setErrorMessage('Elige un centro.');
                  return;
                }
                void run(
                  () => assignTestCenterRole(centerId, email.trim(), role),
                  'Rol asignado.',
                );
              }}
            />
          ))}
        </View>
      </SectionCard>

      <SectionCard title="3. Equino">
        <Text style={styles.hint}>
          Crea antes el equino en Mis equinos, con un nombre TEST_ONLY. Registrarlo no cambia al propietario ni al gestor.
        </Text>
        {ownEquines.map((equine) => (
          <Choice
            key={equine.id}
            label={equine.name}
            selected={equineId === equine.id}
            onPress={() => setEquineId(equine.id)}
          />
        ))}
        <Action
          label="Registrar equino elegido"
          onPress={() => {
            if (!equineId) {
              setErrorMessage('Elige un equino TEST_ONLY.');
              return;
            }
            void run(() => registerTestEquine(equineId), 'Equino registrado.');
          }}
        />
        <Action
          label="Afiliar al centro como SCHOOL"
          onPress={() => {
            if (!equineId || !centerId) {
              setErrorMessage('Elige centro y equino.');
              return;
            }
            void run(
              () => assignTestEquine(equineId, centerId, 'SCHOOL'),
              'Afiliación creada. No es propiedad ni permiso.',
            );
          }}
        />
        <Action
          label="Transferir gestión principal"
          onPress={() => {
            if (!equineId) {
              setErrorMessage('Elige un equino.');
              return;
            }
            void run(
              () => transferTestManager(equineId, email.trim()),
              'La gestión principal ha pasado. La propiedad no cambia.',
            );
          }}
        />
        <Action
          label="Transferir mi propiedad"
          onPress={() => {
            if (!equineId) {
              setErrorMessage('Elige un equino.');
              return;
            }
            void run(
              () => transferTestOwnership(equineId, email.trim()),
              'Tu participación de propiedad ha pasado. La gestión no cambia.',
            );
          }}
        />
      </SectionCard>

      <SectionCard title="4. Permisos del centro sobre el equino">
        <View style={styles.row}>
          {PERMISSIONS.map((permission) => (
            <Action
              key={permission}
              label={permission}
              onPress={() => {
                if (!equineId || !centerId) {
                  setErrorMessage('Elige centro y equino.');
                  return;
                }
                void run(
                  () => grantTestPermission(equineId, centerId, permission),
                  'Permiso concedido.',
                );
              }}
            />
          ))}
        </View>
      </SectionCard>

      <SectionCard title="5. Servicio, ventana y bloqueo">
        <Field label="Servicio" value={serviceName} onChangeText={setServiceName} />
        <Field label="Duración en minutos" value={duration} onChangeText={setDuration} />
        <Action
          label="Crear servicio"
          onPress={() => {
            if (!centerId) {
              setErrorMessage('Elige un centro.');
              return;
            }
            const minutes = Number(duration);
            void run(
              () => createTestService(centerId, serviceName.trim(), minutes),
              'Servicio creado.',
            );
          }}
        />
        {services.map((row) => (
          <Choice
            key={row.entityId}
            label={row.label}
            selected={serviceId === row.entityId}
            onPress={() => setServiceId(row.entityId)}
          />
        ))}
        {equines.map((row) => (
          <Choice
            key={row.entityId}
            label={row.label}
            selected={equineId === row.entityId}
            onPress={() => setEquineId(row.entityId)}
          />
        ))}
        <Action
          label="Enlazar servicio y equino"
          onPress={() => {
            if (!serviceId || !equineId) {
              setErrorMessage('Elige servicio y equino.');
              return;
            }
            void run(
              () => linkTestService(serviceId, equineId),
              'Enlace creado. No añade requisitos de evaluación.',
            );
          }}
        />
        <Field label="Inicio UTC" value={startsAt} onChangeText={setStartsAt} />
        <Field label="Fin UTC" value={endsAt} onChangeText={setEndsAt} />
        <Text style={styles.hint}>Ejemplo: 2026-12-02T09:00:00Z y 2026-12-02T12:00:00Z</Text>
        <Action
          label="Guardar disponibilidad"
          onPress={() => {
            if (!equineId || !centerId) {
              setErrorMessage('Elige centro y equino.');
              return;
            }
            void run(
              () => setTestAvailability(equineId, centerId, startsAt.trim(), endsAt.trim()),
              'Ventana guardada.',
            );
          }}
        />
        <View style={styles.row}>
          {BLOCKS.map((block) => (
            <Action
              key={block}
              label={block}
              onPress={() => {
                if (!equineId || !centerId) {
                  setErrorMessage('Elige centro y equino.');
                  return;
                }
                void run(
                  () => addTestBlock(equineId, centerId, startsAt.trim(), endsAt.trim(), block),
                  'Bloqueo manual creado.',
                );
              }}
            />
          ))}
        </View>
      </SectionCard>

      <SectionCard title="6. Piloto de prueba">
        <Field label="Código" value={pilotCode} onChangeText={setPilotCode} />
        <Action
          label="Hacer visible dentro del piloto"
          onPress={() => {
            if (!equineId) {
              setErrorMessage('Elige un equino.');
              return;
            }
            void run(
              () => markTestVisibility(equineId, 'PUBLIC'),
              'El equino queda PUBLIC. Explorar sigue exigiendo el piloto abierto.',
            );
          }}
        />
        <Action
          label="Abrir piloto y admitir el par"
          onPress={() => {
            if (!centerId || !equineId) {
              setErrorMessage('Elige centro y equino.');
              return;
            }
            void run(
              () => openTestPilot(pilotCode.trim(), centerId, equineId),
              'Piloto abierto. Entra con el jinete y avanza Explorar hasta esa fecha.',
            );
          }}
        />
      </SectionCard>

      <SectionCard title="9. Retirada">
        <Text style={styles.hint}>
          Cierra los pilotos TEST_ONLY y desactiva centros, servicios, ventanas y bloqueos manuales. Conserva auditoría, personas y cuentas. No borra la ocupación de una reserva.
        </Text>
        <Action
          label="Retirar datos de prueba"
          onPress={() => {
            void run(() => retireTestOperatorData(), 'Datos de prueba retirados.');
          }}
        />
      </SectionCard>
    </ScreenScaffold>
  );
}

function Field({
  label,
  value,
  onChangeText,
}: {
  label: string;
  value: string;
  onChangeText: (value: string) => void;
}) {
  return (
    <View style={styles.field}>
      <Text style={styles.label}>{label}</Text>
      <TextInput
        autoCapitalize="none"
        onChangeText={onChangeText}
        style={styles.input}
        value={value}
      />
    </View>
  );
}

function Action({ label, onPress }: { label: string; onPress: () => void }) {
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => [styles.button, pressed && styles.pressed]}
    >
      <Text style={styles.buttonText}>{label}</Text>
    </Pressable>
  );
}

function Choice({
  label,
  selected,
  onPress,
}: {
  label: string;
  selected: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable accessibilityRole="button" onPress={onPress} style={styles.choice}>
      <Text style={selected ? styles.choiceSelected : styles.choiceText}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  error: { color: '#9d1c1c', fontSize: 14, lineHeight: 20, marginBottom: 12 },
  notice: { color: colors.accent, fontSize: 14, lineHeight: 20, marginBottom: 12 },
  hint: { color: colors.muted, fontSize: 14, lineHeight: 20, marginBottom: 8 },
  field: { marginBottom: 8 },
  label: { color: colors.muted, fontSize: 12, marginBottom: 4 },
  input: {
    minHeight: 44,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 8,
    paddingHorizontal: 12,
    color: colors.text,
    backgroundColor: colors.surface,
  },
  row: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  button: {
    minHeight: 44,
    marginTop: 8,
    marginRight: 8,
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
    backgroundColor: colors.text,
  },
  pressed: { opacity: 0.8 },
  buttonText: { color: colors.surface, fontSize: 13, fontWeight: '600' },
  choice: { minHeight: 36, justifyContent: 'center' },
  choiceText: { color: colors.text, fontSize: 14 },
  choiceSelected: { color: colors.accent, fontSize: 14, fontWeight: '700' },
});
