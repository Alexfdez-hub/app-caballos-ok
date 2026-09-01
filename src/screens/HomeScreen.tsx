import type { HomeScreenProps } from '../app/navigation/types';
import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { MenuRow } from '../app/ui/MenuRow';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { useIdentity } from '../features/identity/useIdentity';

export default function HomeScreen({ navigation }: HomeScreenProps) {
  const { identity } = useIdentity();
  const firstName = identity?.firstName ?? '';

  return (
    <ScreenScaffold>
      <ScreenHeader
        title={`Hola, ${firstName}`}
        subtitle="Aquí verás tu día a día ecuestre."
      />

      <SectionCard title="Próxima actividad">
        <EmptyStateCard
          title="No tienes próximas actividades"
          description="Cuando tengas una reserva aparecerá aquí."
        />
      </SectionCard>

      <SectionCard title="Pendientes">
        <EmptyStateCard
          title="No hay reservas ni solicitudes pendientes"
          description="Las peticiones que esperen respuesta se mostrarán en este espacio."
        />
      </SectionCard>

      <SectionCard title="Avisos">
        <EmptyStateCard
          title="No hay avisos importantes"
          description="Si hay algo que requiera tu atención, lo verás aquí."
        />
      </SectionCard>

      <SectionCard title="Accesos rápidos">
        <MenuRow
          label="Explorar"
          description="Busca qué montar, hacer o aprender."
          onPress={() =>
            navigation.navigate('ExploreTab', { screen: 'Explore' })
          }
        />
        <MenuRow
          label="Actividad"
          description="Consulta reservas, solicitudes y calendario."
          onPress={() =>
            navigation.navigate('ActivityTab', { screen: 'Activity' })
          }
        />
        <MenuRow
          isLast
          label="Pasaporte"
          description="Tu recorrido e identidad ecuestre."
          onPress={() =>
            navigation.navigate('PassportTab', { screen: 'Passport' })
          }
        />
      </SectionCard>

      <SectionCard title="Cerca de ti">
        <EmptyStateCard
          title="Explora hípicas y actividades"
          description="Cuando haya centros y servicios cerca, aparecerán recomendaciones aquí."
        />
        <MenuRow
          isLast
          label="Ir a Explorar"
          onPress={() =>
            navigation.navigate('ExploreTab', { screen: 'Explore' })
          }
        />
      </SectionCard>
    </ScreenScaffold>
  );
}
