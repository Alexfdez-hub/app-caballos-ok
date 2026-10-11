export type AuthSubmitOperation = 'signIn' | 'signUp' | 'resend' | 'recover';

let inFlightAuthOperation: AuthSubmitOperation | null = null;

export function beginAuthOperation(operation: AuthSubmitOperation) {
  if (inFlightAuthOperation !== null) {
    return false;
  }

  inFlightAuthOperation = operation;
  return true;
}

export function endAuthOperation(operation: AuthSubmitOperation) {
  if (inFlightAuthOperation === operation) {
    inFlightAuthOperation = null;
  }
}

export function resetAuthOperations() {
  inFlightAuthOperation = null;
}
