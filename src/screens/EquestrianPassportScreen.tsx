import { MenuRow } from '../app/ui/MenuRow';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';
import { useIdentity } from '../features/identity/useIdentity';

const PASSPORT_SECTIONS = [
  {
    label: 'Perfil ecuestre',
    description: 'Quién eres como jinete.',
  },
  {
    label: 'Disciplinas',
    description: 'Especialidades en las que participas.',
  },
  {
    label: 'Experiencia',
    description: 'Recorrido y trayectoria.',
  },
  {
    label: 'Galopes / cualificaciones',
    description: 'Niveles y sistemas de cualificación.',
  },
  {
    label: 'Evaluaciones de hípicas',
    description: 'Valoraciones realizadas por centros.',
  },
  {
    label: 'Sesiones verificadas',
    description: 'Actividad ecuestre con evidencia.',
  },
  {
    label: 'Horas de monta',
    description: 'Tiempo de monta acumulado.',
  },
  {
    label: 'Equinos montados',
    description: 'Caballos y ponis con los que has montado.',
  },
  {
    label: 'Centros visitados',
    description: 'Hípicas en las que has participado.',
  },
] as const;

export default function EquestrianPassportScreen() {
  const { identity } = useIdentity();
  const fullName = [identity?.firstName, identity?.lastName]
    .filter(Boolean)
    .join(' ');

  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Pasaporte ecuestre"
        subtitle="Tu trayectoria, experiencia y acreditaciones ecuestres."
      />

      <SectionCard title={fullName || 'Identidad'}>
        {PASSPORT_SECTIONS.map((section, index) => (
          <MenuRow
            key={section.label}
            description={section.description}
            isLast={index === PASSPORT_SECTIONS.length - 1}
            label={section.label}
            status="empty"
          />
        ))}
      </SectionCard>
    </ScreenScaffold>
  );
}
