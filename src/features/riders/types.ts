export type ProfileVisibility = 'PRIVATE' | 'PUBLIC';

export type RiderProfile = {
  personId: string;
  bio: string | null;
  experienceStartYear: number | null;
  profileVisibility: ProfileVisibility;
  createdAt: string;
  updatedAt: string;
};

export type UpsertRiderProfileInput = {
  bio: string | null;
  experienceStartYear: number | null;
  profileVisibility: ProfileVisibility;
};
