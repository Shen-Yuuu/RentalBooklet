export class LayoutSpec {
  bedrooms: number;
  livingRooms: number;
  bathrooms: number;
  balconies: number;

  constructor(bedrooms: number, livingRooms: number, bathrooms: number, balconies: number) {
    this.bedrooms = bedrooms;
    this.livingRooms = livingRooms;
    this.bathrooms = bathrooms;
    this.balconies = balconies;
  }
}

export class LayoutError extends Error {
  constructor(message: string) {
    super(message);
  }
}

/** 户型 "室-厅-卫-阳台"（如 2-1-1-1）与 LayoutSpec 的互转。 */
export class LayoutUtil {
  static readonly SEPARATOR: string = '-';
  static readonly FIELD_COUNT: number = 4;

  static parse(text: string): LayoutSpec {
    const parts: string[] = text.split(LayoutUtil.SEPARATOR);
    if (parts.length !== LayoutUtil.FIELD_COUNT) {
      throw new LayoutError(`户型格式应为"室-厅-卫-阳台"四个数字，收到: ${text}`);
    }
    const nums: number[] = [];
    for (const p of parts) {
      const t: string = p.trim();
      if (t.length === 0) {
        throw new LayoutError(`户型数字不合法: ${text}`);
      }
      const v: number = Number(t);
      if (!Number.isInteger(v) || v < 0 || v > 9) {
        throw new LayoutError(`户型数字不合法: ${text}`);
      }
      nums.push(v);
    }
    return new LayoutSpec(nums[0], nums[1], nums[2], nums[3]);
  }

  static format(spec: LayoutSpec): string {
    return `${spec.bedrooms}-${spec.livingRooms}-${spec.bathrooms}-${spec.balconies}`;
  }

  /** 展示文案，如 "2室1厅1卫1阳台"。 */
  static describe(spec: LayoutSpec): string {
    return `${spec.bedrooms}室${spec.livingRooms}厅${spec.bathrooms}卫${spec.balconies}阳台`;
  }

  static describeText(layout: string): string {
    return LayoutUtil.describe(LayoutUtil.parse(layout));
  }
}
