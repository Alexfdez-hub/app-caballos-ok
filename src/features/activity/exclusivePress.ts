export type ExclusivePress = {
  held: boolean;
  generation: number;
};

export function idleExclusivePress(): ExclusivePress {
  return { held: false, generation: 0 };
}

export function beginExclusivePress(state: ExclusivePress): {
  state: ExclusivePress;
  generation: number | null;
} {
  if (state.held) {
    return { state, generation: null };
  }

  const generation = state.generation + 1;
  return {
    generation,
    state: { held: true, generation },
  };
}

export function endExclusivePress(state: ExclusivePress, generation: number): ExclusivePress {
  if (!state.held || state.generation !== generation) {
    return state;
  }

  return { held: false, generation: state.generation };
}

export function mayPublishExclusiveResult(
  state: ExclusivePress,
  generation: number,
  isScreenActive: boolean,
  requestedUserId: string | null,
  currentUserId: string | null,
): boolean {
  return (
    state.held &&
    state.generation === generation &&
    isScreenActive &&
    requestedUserId !== null &&
    requestedUserId === currentUserId
  );
}
