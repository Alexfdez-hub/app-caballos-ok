export type AccountRead<T> = {
  ownerUserId: string | null;
  rows: T[];
  errorMessage: string | null;
  isLoading: boolean;
  requestSeq: number;
};

export function idleAccountRead<T>(userId: string | null): AccountRead<T> {
  return {
    ownerUserId: userId,
    rows: [],
    errorMessage: null,
    isLoading: userId !== null,
    requestSeq: 0,
  };
}

export function retargetAccountRead<T>(
  current: AccountRead<T>,
  userId: string | null,
): AccountRead<T> {
  if (current.ownerUserId === userId) {
    return current;
  }

  return {
    ownerUserId: userId,
    rows: [],
    errorMessage: null,
    isLoading: userId !== null,
    requestSeq: current.requestSeq + 1,
  };
}

export function beginAccountRead<T>(
  current: AccountRead<T>,
  userId: string | null,
  requestSeq: number,
): AccountRead<T> {
  const sameOwner = current.ownerUserId === userId;
  return {
    ownerUserId: userId,
    rows: sameOwner ? current.rows : [],
    errorMessage: null,
    isLoading: userId !== null,
    requestSeq,
  };
}

export function settleAccountRead<T>(
  current: AccountRead<T>,
  incoming: {
    requestSeq: number;
    requestedUserId: string | null;
    currentUserId: string | null;
    screenActive: boolean;
    ok: boolean;
    rows: T[];
    errorMessage: string | null;
  },
): AccountRead<T> {
  const sameAccount =
    incoming.screenActive &&
    incoming.requestSeq === current.requestSeq &&
    incoming.requestedUserId !== null &&
    incoming.requestedUserId === incoming.currentUserId &&
    incoming.currentUserId === current.ownerUserId;
  if (!sameAccount) {
    return current;
  }

  if (incoming.ok) {
    return {
      ownerUserId: incoming.currentUserId,
      rows: incoming.rows,
      errorMessage: null,
      isLoading: false,
      requestSeq: current.requestSeq,
    };
  }

  return {
    ownerUserId: incoming.currentUserId,
    rows: [],
    errorMessage: incoming.errorMessage,
    isLoading: false,
    requestSeq: current.requestSeq,
  };
}

export function presentAccountSnapshot<T>(
  snapshot: AccountRead<T>,
  currentUserId: string | null,
): {
  rows: T[];
  errorMessage: string | null;
  isLoading: boolean;
  owned: boolean;
} {
  const owned = currentUserId !== null && snapshot.ownerUserId === currentUserId;
  if (!owned) {
    return {
      rows: [],
      errorMessage: null,
      isLoading: currentUserId !== null,
      owned: false,
    };
  }

  return {
    rows: snapshot.rows,
    errorMessage: snapshot.errorMessage,
    isLoading: snapshot.isLoading,
    owned: true,
  };
}
