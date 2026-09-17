import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * 运行时能力分支：API 26+ 专属特性封装在独立组件中，
 * 仅在 isApi26Plus 为 true 时实例化，6.0.1(21) 设备永不加载新组件。
 */
export class DeviceCapability {
  static readonly isApi26Plus: boolean = deviceInfo.sdkApiVersion >= 26;
}
