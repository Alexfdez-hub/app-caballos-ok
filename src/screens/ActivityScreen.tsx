import { EmptyStateCard } from '../app/ui/EmptyStateCard';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';

export default function ActivityScreen() {
  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Actividad"
        subtitle="Reservas, solicitudes y sesiones."
      />

      <SectionCard title="Próximas">
        <EmptyStateCard
          title="No tienes próximas actividades"
          description="Cuando una reserva quede confirmada, aparecerá aquí."
        />
      </SectionCard>

      <SectionCard title="Solicitudes">
        <EmptyStateCard
          title="No hay solicitudes abiertas"
          description="Las peticiones de reserva pendientes de respuesta se mostrarán en esta lista."
        />
      </SectionCard>

      <SectionCard title="Calendario">
        <EmptyStateCard
          title="Todavía no hay calendario"
          description="Aquí verás la ocupación de tus actividades cuando existan reservas."
        />
      </SectionCard>

      <SectionCard title="Historial">
        <EmptyStateCard
          title="Aún no hay historial"
          description="Las sesiones verificables y la Sesión Cero aparecerán aquí cuando existan."
        />
      </SectionCard>
    </ScreenScaffold>
  );
}
