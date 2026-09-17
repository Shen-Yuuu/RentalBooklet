import { geoLocationManager } from '@kit.LocationKit';

export interface GeoPoint {
  lat: number;
  lng: number;
}

/** 定位：仅当用户开启"记录位置"并授权后使用；任何失败返回 null，不阻塞拍照。 */
export class LocationService {
  static async currentPoint(): Promise<GeoPoint | null> {
    try {
      const loc = await geoLocationManager.getCurrentLocation();
      const point: GeoPoint = { lat: loc.latitude, lng: loc.longitude };
      return point;
    } catch (err) {
      return null;
    }
  }
}
