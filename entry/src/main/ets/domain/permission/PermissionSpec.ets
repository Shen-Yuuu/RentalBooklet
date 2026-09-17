export enum PermissionGrant {
  NOT_DETERMINED = 0,
  GRANTED = 1,
  DENIED = 2
}

export interface PermissionFeature {
  key: string;
  permissions: string[];
  /** $string 资源名：设置页/权限引导文案引用。 */
  reasonKey: string;
}

export const FEATURE_SPEECH_NOTE: string = 'speech_note';
export const FEATURE_PHOTO_LOCATION: string = 'photo_location';

export const PERMISSION_FEATURES: PermissionFeature[] = [
  { key: FEATURE_SPEECH_NOTE, permissions: ['ohos.permission.MICROPHONE'], reasonKey: 'perm_mic_reason' },
  {
    key: FEATURE_PHOTO_LOCATION,
    permissions: ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'],
    reasonKey: 'perm_location_reason'
  }
];

export function featurePermissions(featureKey: string): string[] {
  for (const f of PERMISSION_FEATURES) {
    if (f.key === featureKey) {
      return f.permissions;
    }
  }
  return [];
}

/** requestPermissionsFromUser 的 authResults：0=授予，其余=拒绝。 */
export function authResultToGrant(authResult: number): PermissionGrant {
  return authResult === 0 ? PermissionGrant.GRANTED : PermissionGrant.DENIED;
}

/** 权限组（如位置粗+精）必须全部授予才算 GRANTED。 */
export function groupGrant(results: PermissionGrant[]): PermissionGrant {
  if (results.length === 0) {
    return PermissionGrant.NOT_DETERMINED;
  }
  for (const r of results) {
    if (r !== PermissionGrant.GRANTED) {
      return PermissionGrant.DENIED;
    }
  }
  return PermissionGrant.GRANTED;
}
