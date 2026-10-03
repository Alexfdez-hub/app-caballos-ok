export type Identity = {
  userAccountId: string;
  personId: string;
  firstName: string | null;
  lastName: string | null;
  dateOfBirth: string | null;
  countryCode: string | null;
  isComplete: boolean;
};

export type CompleteIdentityInput = {
  firstName: string;
  lastName: string;
  dateOfBirth: string;
  countryCode: string;
};

export type IdentityMarket = {
  countryCode: string;
  defaultLocale: string | null;
};
