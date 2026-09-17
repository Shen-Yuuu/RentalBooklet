import { camera, cameraPicker } from '@kit.CameraKit';

/**
 * 拍照：走系统相机选择器，应用无需申请相机权限。
 * 取消/失败返回 null，调用方静默处理。
 */
export class CaptureService {
  static async takePhoto(ctx: Context): Promise<string | null> {
    try {
      const profile: cameraPicker.PickerProfile = { cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK };
      const result = await cameraPicker.pick(ctx, [cameraPicker.PickerMediaType.PHOTO], profile);
      if (result.resultCode === 0 && result.resultUri.length > 0) {
        return result.resultUri;
      }
      return null;
    } catch (err) {
      const e = err as Error;
      return null;
    }
  }
}
