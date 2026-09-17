import { mediaquery } from '@kit.ArkUI';

/**
 * 宽屏断点监听器（F2）：官方 lg 断点 = 窗口宽度 ≥840vp。
 * 组件 aboutToAppear 时 attach、aboutToDisappear 时 detach；
 * 回调运行在 UI 线程，直接写组件 @State 即可触发重渲染。
 */
export class WideBreakpointWatcher {
  private listener: mediaquery.MediaQueryListener | undefined = undefined;
  private wide: boolean = false;
  private uiContext: UIContext;
  private onChange: (wide: boolean) => void;

  constructor(uiContext: UIContext, onChange: (wide: boolean) => void) {
    this.uiContext = uiContext;
    this.onChange = onChange;
  }

  attach(): void {
    this.listener = this.uiContext.getMediaQuery().matchMediaSync('(840vp<=width)');
    this.wide = this.listener.matches;
    this.onChange(this.wide);
    this.listener.on('change', (result: mediaquery.MediaQueryResult) => {
      this.wide = result.matches;
      this.onChange(this.wide);
    });
  }

  detach(): void {
    if (this.listener !== undefined) {
      this.listener.off('change');
      this.listener = undefined;
    }
  }

  get isWide(): boolean {
    return this.wide;
  }
}
