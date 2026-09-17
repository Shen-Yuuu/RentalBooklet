export class DateUtil {
  private static pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  static formatDateTime(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const d = new Date(ts);
    return `${d.getFullYear()}-${DateUtil.pad(d.getMonth() + 1)}-${DateUtil.pad(d.getDate())} `
      + `${DateUtil.pad(d.getHours())}:${DateUtil.pad(d.getMinutes())}`;
  }

  static formatDate(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const d = new Date(ts);
    return `${d.getFullYear()}-${DateUtil.pad(d.getMonth() + 1)}-${DateUtil.pad(d.getDate())}`;
  }
}
