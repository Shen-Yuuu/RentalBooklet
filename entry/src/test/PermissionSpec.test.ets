import { describe, it, expect } from '@ohos/hypium';
import {
  FEATURE_PHOTO_LOCATION,
  FEATURE_SPEECH_NOTE,
  PermissionGrant,
  authResultToGrant,
  featurePermissions,
  groupGrant
} from '../main/ets/domain/permission/PermissionSpec';

export default function permissionSpecTest(): void {
  describe('PermissionSpec', () => {
    it('auth_result_mapping', 0, () => {
      expect(authResultToGrant(0)).assertEqual(PermissionGrant.GRANTED);
      expect(authResultToGrant(-1)).assertEqual(PermissionGrant.DENIED);
    });

    it('group_requires_all_granted', 0, () => {
      expect(groupGrant([PermissionGrant.GRANTED, PermissionGrant.GRANTED])).assertEqual(PermissionGrant.GRANTED);
      expect(groupGrant([PermissionGrant.GRANTED, PermissionGrant.DENIED])).assertEqual(PermissionGrant.DENIED);
      expect(groupGrant([PermissionGrant.DENIED])).assertEqual(PermissionGrant.DENIED);
      expect(groupGrant([])).assertEqual(PermissionGrant.NOT_DETERMINED);
    });

    it('feature_lookup', 0, () => {
      const mic = featurePermissions(FEATURE_SPEECH_NOTE);
      expect(mic.length).assertEqual(1);
      expect(mic[0]).assertEqual('ohos.permission.MICROPHONE');

      const loc = featurePermissions(FEATURE_PHOTO_LOCATION);
      expect(loc.length).assertEqual(2);

      expect(featurePermissions('no_such_feature').length).assertEqual(0);
    });
  });
}
