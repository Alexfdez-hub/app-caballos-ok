import { MenuRow } from '../app/ui/MenuRow';
import { ScreenHeader } from '../app/ui/ScreenHeader';
import { ScreenScaffold } from '../app/ui/ScreenScaffold';
import { SectionCard } from '../app/ui/SectionCard';

export default function ExploreScreen() {
  return (
    <ScreenScaffold>
      <ScreenHeader
        title="Explorar"
        subtitle="¿Qué puedo montar, hacer o aprender cerca de mí?"
      />

      <SectionCard title="Descubrir">
        <MenuRow
          label="Caballos y ponis"
          description="Los equinos existen como dominio, pero el directorio público, la disponibilidad, las reservas y la subida de media aún no están en la app."
          status="comingSoon"
        />
        <MenuRow
          label="Hípicas"
          description="Los centros existen como dominio, pero el alta, la verificación y el directorio público aún no están en la app."
          status="comingSoon"
        />
        <MenuRow
          label="Clases"
          description="Aprendizaje con seguimiento."
          status="comingSoon"
        />
        <MenuRow
          label="Rutas"
          description="Salidas y recorridos en el exterior."
          status="comingSoon"
        />
        <MenuRow
          isLast
          label="Cursos y actividades"
          description="Formación y experiencias puntuales."
          status="comingSoon"
        />
      </SectionCard>

      <SectionCard title="Buscar">
        <MenuRow
          label="Mapa"
          description="Ver qué hay alrededor."
          status="comingSoon"
        />
        <MenuRow
          isLast
          label="Filtros"
          description="Afinar por disciplina, nivel o distancia."
          status="comingSoon"
        />
      </SectionCard>
    </ScreenScaffold>
  );
}
