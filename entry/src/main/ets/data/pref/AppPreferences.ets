import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

const PREF_NAME: string = 'app_prefs';

export const KEY_DISCLAIMER_ACCEPTED: string = 'disclaimer_accepted';
/** F4：首次建档提示是否已展示过（一次性提示）。 */
export const KEY_HOUSE_CREATE_HINT_SHOWN: string = 'house_create_hint_shown';

export class AppPreferences {
  private static async store(context: common.UIAbilityContext): Promise<preferences.Preferences> {
    try {
      return await preferences.getPreferences(context, { name: PREF_NAME });
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`偏好存储打开失败 code=${e.code}`);
    }
  }

  static async getBool(context: common.UIAbilityContext, key: string, def: boolean): Promise<boolean> {
    try {
      const s = await AppPreferences.store(context);
      const v = await s.get(key, def);
      return v as boolean;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`偏好读取失败 key=${key} code=${e.code}`);
    }
  }

  static async setBool(context: common.UIAbilityContext, key: string, value: boolean): Promise<void> {
    try {
      const s = await AppPreferences.store(context);
      await s.put(key, value);
      await s.flush();
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`偏好写入失败 key=${key} code=${e.code}`);
    }
  }

  static async getString(context: common.UIAbilityContext, key: string, def: string): Promise<string> {
    try {
      const s = await AppPreferences.store(context);
      const v = await s.get(key, def);
      return v as string;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`偏好读取失败 key=${key} code=${e.code}`);
    }
  }

  static async setString(context: common.UIAbilityContext, key: string, value: string): Promise<void> {
    try {
      const s = await AppPreferences.store(context);
      await s.put(key, value);
      await s.flush();
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`偏好写入失败 key=${key} code=${e.code}`);
    }
  }
}
