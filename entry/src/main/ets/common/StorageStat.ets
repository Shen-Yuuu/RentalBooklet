import { fileIo as fs, statfs } from '@kit.CoreFileKit';

/** 存储占用统计（F3 设置页看板）：沙箱目录递归求和 + 数据库文件统计。全部容错，失败返回 0。 */
export class StorageStat {
  /**
   * 沙箱所在文件系统剩余可用字节数（L4 拍前存储预检）。
   * 查询失败返回 -1，调用方按"未知"放行，不阻塞拍摄。
   */
  static async freeBytes(dir: string): Promise<number> {
    try {
      return await statfs.getFreeSize(dir);
    } catch (err) {
      return -1;
    }
  }

  /** 递归统计目录总字节数。目录不存在返回 0；单条目读取失败跳过。 */
  static dirSize(dir: string): number {
    try {
      if (!fs.accessSync(dir)) {
        return 0;
      }
    } catch (err) {
      return 0;
    }
    let total = 0;
    try {
      const names = fs.listFileSync(dir);
      for (const name of names) {
        const full = `${dir}/${name}`;
        try {
          const stat = fs.statSync(full);
          if (stat.isDirectory()) {
            total += StorageStat.dirSize(full);
          } else {
            total += stat.size;
          }
        } catch (err) {
          // 单条目 stat 失败跳过
        }
      }
    } catch (err) {
      return total;
    }
    return total;
  }

  /** 数据库占用字节数：rental.db 本体及 wal/shm 等同前缀辅助文件。 */
  static dbSize(databaseDir: string, dbName: string): number {
    let total = 0;
    try {
      if (!fs.accessSync(databaseDir)) {
        return 0;
      }
      const names = fs.listFileSync(databaseDir);
      for (const name of names) {
        if (name === dbName || name.startsWith(`${dbName}-`)) {
          try {
            const stat = fs.statSync(`${databaseDir}/${name}`);
            total += stat.size;
          } catch (err) {
            // 单条目 stat 失败跳过
          }
        }
      }
    } catch (err) {
      return total;
    }
    return total;
  }
}
