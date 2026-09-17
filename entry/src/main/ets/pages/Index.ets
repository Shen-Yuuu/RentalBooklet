import { common } from '@kit.AbilityKit';
import { AppPreferences, KEY_DISCLAIMER_ACCEPTED } from '../data/pref/AppPreferences';
import { DisclaimerDialog } from '../features/settings/DisclaimerDialog';
import { Routes } from '../common/Routes';
import { InspectionParam } from '../common/NavParams';
import { DeviceCapability } from '../common/DeviceCapability';
import { IndexTabsLegacy } from '../features/shell/IndexTabsLegacy';
import { IndexTabsModern } from '../features/shell/IndexTabsModern';

@Entry
@Component
struct Index {
  @Provide('navPathStack') pathStack: NavPathStack = new NavPathStack();
  @State showDisclaimer: boolean = false;
  /** 免责声明已同意：深链仅在其为 true 后消费（首次启动先声明后跳转）。 */
  @State disclaimerAccepted: boolean = false;
  /** 卡片深链（F1）：EntryAbility 写入，@Watch + aboutToAppear 双入口消费。 */
  @StorageProp('deeplink_inspection_id') @Watch('onDeepLinkChanged') deepLinkId: number = 0;

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppPreferences.getBool(ctx, KEY_DISCLAIMER_ACCEPTED, false).then((accepted: boolean) => {
      this.disclaimerAccepted = accepted;
      if (!accepted) {
        this.showDisclaimer = true;
      } else {
        this.consumeDeepLink();
      }
    });
  }

  private onDeepLinkChanged(): void {
    this.consumeDeepLink();
  }

  /** 消费卡片深链：免责声明同意前不跳转；置 0 防重复消费（@Watch 对 0 不再触发跳转）。 */
  private consumeDeepLink(): void {
    if (this.deepLinkId <= 0 || !this.disclaimerAccepted) {
      return;
    }
    const id = this.deepLinkId;
    AppStorage.setOrCreate('deeplink_inspection_id', 0);
    this.pathStack.pushPathByName(Routes.INSPECTION, { inspectionId: id } as InspectionParam);
  }

  build() {
    Navigation(this.pathStack) {
      if (DeviceCapability.isApi26Plus) {
        IndexTabsModern()
      } else {
        IndexTabsLegacy()
      }
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
    .bindContentCover($$this.showDisclaimer, this.disclaimerView(), {
      onWillDismiss: (action: DismissContentCoverAction) => {
        // 首次使用必须显式选择同意或退出，不允许点击遮罩/侧滑关闭
      }
    })
  }

  @Builder
  disclaimerView() {
    DisclaimerDialog({
      onAccept: () => {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        AppPreferences.setBool(ctx, KEY_DISCLAIMER_ACCEPTED, true).then(() => {
          this.showDisclaimer = false;
          this.disclaimerAccepted = true;
          // 同意后补消费待处理的深链
          this.consumeDeepLink();
        });
      },
      onDecline: () => {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        ctx.terminateSelf();
      }
    })
  }
}
