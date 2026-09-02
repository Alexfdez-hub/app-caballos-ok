import type { BottomTabScreenProps } from '@react-navigation/bottom-tabs';
import type {
  CompositeScreenProps,
  NavigatorScreenParams,
} from '@react-navigation/native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';

export type PublicStackParamList = {
  Auth: undefined;
  ForgotPassword: undefined;
};

export type RecoveryStackParamList = {
  UpdatePassword: undefined;
};

export type HomeStackParamList = {
  Home: undefined;
};

export type ExploreStackParamList = {
  Explore: undefined;
};

export type ActivityStackParamList = {
  Activity: undefined;
};

export type PassportStackParamList = {
  Passport: undefined;
  EditRiderProfile: undefined;
};

export type ProfileStackParamList = {
  Profile: undefined;
  EditIdentity: undefined;
  GuardianRelationships: undefined;
  MyCenters: undefined;
};

export type AuthenticatedTabParamList = {
  HomeTab: NavigatorScreenParams<HomeStackParamList>;
  ExploreTab: NavigatorScreenParams<ExploreStackParamList>;
  ActivityTab: NavigatorScreenParams<ActivityStackParamList>;
  PassportTab: NavigatorScreenParams<PassportStackParamList>;
  ProfileTab: NavigatorScreenParams<ProfileStackParamList>;
};

export type HomeScreenProps = CompositeScreenProps<
  NativeStackScreenProps<HomeStackParamList, 'Home'>,
  BottomTabScreenProps<AuthenticatedTabParamList>
>;

export type ExploreScreenProps = CompositeScreenProps<
  NativeStackScreenProps<ExploreStackParamList, 'Explore'>,
  BottomTabScreenProps<AuthenticatedTabParamList>
>;

export type ActivityScreenProps = CompositeScreenProps<
  NativeStackScreenProps<ActivityStackParamList, 'Activity'>,
  BottomTabScreenProps<AuthenticatedTabParamList>
>;

export type PassportScreenProps = CompositeScreenProps<
  NativeStackScreenProps<PassportStackParamList, 'Passport'>,
  BottomTabScreenProps<AuthenticatedTabParamList>
>;

export type EditRiderProfileScreenProps = NativeStackScreenProps<
  PassportStackParamList,
  'EditRiderProfile'
>;

export type ProfileScreenProps = CompositeScreenProps<
  NativeStackScreenProps<ProfileStackParamList, 'Profile'>,
  BottomTabScreenProps<AuthenticatedTabParamList>
>;

export type EditIdentityScreenProps = NativeStackScreenProps<
  ProfileStackParamList,
  'EditIdentity'
>;

export type MyCentersScreenProps = NativeStackScreenProps<
  ProfileStackParamList,
  'MyCenters'
>;
