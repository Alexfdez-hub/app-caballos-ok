export type AuthSubmitOperation = 'signIn' | 'signUp' | 'resend' | 'recover';

const inFlightAuthOperations = new Set<AuthSubmitOperation>();

export function beginAuthOperation(operation: AuthSubmitOperation) {
  if (inFlightAuthOperations.has(operation)) {
    return false;
  }

  inFlightAuthOperations.add(operation);
  return true;
}

export function endAuthOperation(operation: AuthSubmitOperation) {
  inFlightAuthOperations.delete(operation);
}

export function resetAuthOperations() {
  inFlightAuthOperations.clear();
}
