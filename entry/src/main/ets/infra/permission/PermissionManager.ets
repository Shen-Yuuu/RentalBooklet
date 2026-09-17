import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PermissionGrant, authResultToGrant, featurePermissions, groupGrant } from '../../domain/permission/PermissionSpec';

/** AbilityKit 权限 API 的薄封装；授予/组合等纯逻辑见 domain/permission/PermissionSpec。 */
export class PermissionManager {
  /** 查询单个权限当前授予状态。 */
  static async currentGrant(context: common.UIAbilityContext, permission: Permissions): Promise<PermissionGrant> {
    const atManager = abilityAccessCtrl.createAtManager();
    try {
      const tokenId: number = PermissionManager.selfTokenId();
      const status = await atManager.checkAccessToken(tokenId, permission);
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
        ? PermissionGrant.GRANTED : PermissionGrant.DENIED;
    } catch (err) {
      const e = err as BusinessError;
      return PermissionGrant.DENIED;
    }
  }

  /** 申请某功能所需权限组；组内全部授予才返回 GRANTED。无需权限的功能直接放行。 */
  static async requestFeature(context: common.UIAbilityContext, featureKey: string): Promise<PermissionGrant> {
    const perms: string[] = featurePermissions(featureKey);
    if (perms.length === 0) {
      return PermissionGrant.GRANTED;
    }
    const atManager = abilityAccessCtrl.createAtManager();
    try {
      const result = await atManager.requestPermissionsFromUser(context, perms as Permissions[]);
      const grants: PermissionGrant[] = [];
      for (const r of result.authResults) {
        grants.push(authResultToGrant(r));
      }
      return groupGrant(grants);
    } catch (err) {
      const e = err as BusinessError;
      return PermissionGrant.DENIED;
    }
  }

  private static selfTokenId(): number {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    return info.appInfo.accessTokenId;
  }
}
