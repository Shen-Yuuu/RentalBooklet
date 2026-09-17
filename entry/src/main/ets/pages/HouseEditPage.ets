import { common } from '@kit.AbilityKit';
import { House, Inspection } from '../domain/model/Entities';
import { LayoutSpec, LayoutUtil } from '../common/LayoutUtil';
import { HouseRepo } from '../data/repo/HouseRepo';
import { AppPreferences, KEY_HOUSE_CREATE_HINT_SHOWN } from '../data/pref/AppPreferences';
import { InspectionLauncher } from '../features/inspection/InspectionLauncher';
import { BaselinePickerSheet } from '../features/inspection/BaselinePickerSheet';
import { HousePrepareParam } from '../common/NavParams';
import { SceneKey } from '../domain/model/CoreEnums';

@Builder
export function houseEditBuilder() {
  HouseEditPage();
}

/** 检查准备页：从已有房屋中选择，或新建档案后开始检查。 */
@Component
struct HouseEditPage {
  @State sceneKey: string = '';
  @State houses: House[] = [];
  @State selectedHouseId: number = 0;
  @State showForm: boolean = true;
  @State houseName: string = '';
  @State bedrooms: number = 2;
  @State livingRooms: number = 1;
  @State bathrooms: number = 1;
  @State balconies: number = 1;
  @State fullAddress: string = '';
  @State landlordName: string = '';
  @State landlordPhone: string = '';
  @State tenantName: string = '';
  @State tenantPhone: string = '';
  @State recordLocation: boolean = false;
  @State busy: boolean = false;
  @State errorText: string = '';
  /** 档案编辑模式（houseId>0）：仅编辑保存档案，不发起检查。 */
  @State editHouseId: number = 0;
  /** E1 基线选择：候选与半模态开关（退租场景 + 已有房屋时）。 */
  @State baselineCandidates: Inspection[] = [];
  @State showBaselineSheet: boolean = false;
  private pendingHouseId: number = 0;
  private pendingHouseName: string = '';
  /** 编辑模式加载的原档案（保留 createdAt/leaseEndDate 等表单外字段）。 */
  private editingHouse: House = new House();
  private pathStack: NavPathStack = new NavPathStack();

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Scroll() {
          Column({ space: 12 }) {
            Text(this.editHouseId > 0 ? '编辑房屋档案'
              : `${InspectionLauncher.sceneTitleOf(this.sceneKey)} · 检查对象`)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .width('100%')

            if (this.editHouseId <= 0) {
              ForEach(this.houses, (h: House) => {
                Row({ space: 10 }) {
                  Radio({ value: `${h.id}`, group: 'housePick' })
                    .checked(this.selectedHouseId === h.id)
                    .onChange((isChecked: boolean) => {
                      if (isChecked) {
                        this.selectedHouseId = h.id;
                        this.showForm = false;
                      }
                    })
                  Column({ space: 2 }) {
                    Text(h.name).fontSize(16).fontWeight(FontWeight.Medium)
                    Text(LayoutUtil.describeText(h.layout)).fontSize(12).opacity(0.6)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding(12)
                .borderRadius(12)
                .border({ width: 1, color: this.selectedHouseId === h.id ? $r('app.color.brand') : Color.Transparent })
                .backgroundColor($r('app.color.card_bg'))
              }, (h: House) => `${h.id}`)

              Button(this.showForm ? '收起新建表单' : '＋ 新建房屋档案')
                .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
                .fontSize(14)
                .height(36)
                .onClick(() => {
                  this.showForm = !this.showForm;
                  if (this.showForm) {
                    this.selectedHouseId = 0;
                  }
                })
            }

            if (this.showForm) {
              this.houseForm()
            }

            if (this.errorText.length > 0) {
              Text(this.errorText).fontSize(13).fontColor($r('app.color.danger')).width('100%')
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Auto)

        Button(this.busy ? (this.editHouseId > 0 ? '保存中…' : '创建中…')
          : (this.editHouseId > 0 ? '保存修改' : '开始检查'))
          .width('100%')
          .height(44)
          .enabled(!this.busy && this.canStart())
          .onClick(() => {
            if (this.editHouseId > 0) {
              this.saveEdit();
            } else {
              this.start();
            }
          })
      }
      .padding(16)
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
      .bindSheet($$this.showBaselineSheet, this.baselineSheetBuilder(), { height: 380 })
    }
    .title(this.editHouseId > 0 ? '房屋档案' : '检查准备')
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p = ctx.pathInfo.param as HousePrepareParam | null;
      if (p !== null && p !== undefined) {
        this.sceneKey = p.sceneKey;
        if (p.houseId !== undefined && p.houseId > 0) {
          this.editHouseId = p.houseId;
          this.showForm = true;
          this.loadForEdit();
          return;
        }
      }
      this.loadHouses();
    })
  }

  @Builder
  houseForm() {
    Column({ space: 10 }) {
      Text('房屋简称（必填）').fontSize(13).opacity(0.7).width('100%')
      TextInput({ text: this.houseName, placeholder: '如：滨江公寓 1508' })
        .width('100%')
        .onChange((v: string) => {
          this.houseName = v;
        })

      Text('户型').fontSize(13).opacity(0.7).width('100%')
      Row({ space: 12 }) {
        this.stepper('室', () => this.bedrooms, (v: number) => {
          this.bedrooms = v;
        })
        this.stepper('厅', () => this.livingRooms, (v: number) => {
          this.livingRooms = v;
        })
        this.stepper('卫', () => this.bathrooms, (v: number) => {
          this.bathrooms = v;
        })
        this.stepper('阳台', () => this.balconies, (v: number) => {
          this.balconies = v;
        })
      }
      .width('100%')

      Text('完整地址（选填，默认隐藏）').fontSize(13).opacity(0.7).width('100%')
      TextInput({ text: this.fullAddress, placeholder: '仅导出报告时按需使用' })
        .width('100%')
        .onChange((v: string) => {
          this.fullAddress = v;
        })

      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text('房东称呼').fontSize(13).opacity(0.7)
          TextInput({ text: this.landlordName, placeholder: '选填' })
            .onChange((v: string) => {
              this.landlordName = v;
            })
        }
        .layoutWeight(1)
        Column({ space: 4 }) {
          Text('房东手机').fontSize(13).opacity(0.7)
          TextInput({ text: this.landlordPhone, placeholder: '选填' })
            .type(InputType.PhoneNumber)
            .onChange((v: string) => {
              this.landlordPhone = v;
            })
        }
        .layoutWeight(1)
      }
      .width('100%')

      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text('租客称呼').fontSize(13).opacity(0.7)
          TextInput({ text: this.tenantName, placeholder: '选填' })
            .onChange((v: string) => {
              this.tenantName = v;
            })
        }
        .layoutWeight(1)
        Column({ space: 4 }) {
          Text('租客手机').fontSize(13).opacity(0.7)
          TextInput({ text: this.tenantPhone, placeholder: '选填' })
            .type(InputType.PhoneNumber)
            .onChange((v: string) => {
              this.tenantPhone = v;
            })
        }
        .layoutWeight(1)
      }
      .width('100%')

      Row() {
        Text('为照片记录位置（默认关）').fontSize(14)
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.recordLocation })
          .onChange((isOn: boolean) => {
            this.recordLocation = isOn;
          })
      }
      .width('100%')
    }
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_bg'))
    .width('100%')
  }

  @Builder
  stepper(label: string, getV: () => number, setV: (v: number) => void) {
    Column({ space: 4 }) {
      Text(label).fontSize(12).opacity(0.7)
      Row({ space: 6 }) {
        Button('-')
          .width(28).height(28).fontSize(16)
          .padding(0)
          .onClick(() => {
            setV(Math.max(0, getV() - 1));
          })
        Text(`${getV()}`).fontSize(16).width(20).textAlign(TextAlign.Center)
        Button('+')
          .width(28).height(28).fontSize(16)
          .padding(0)
          .onClick(() => {
            setV(Math.min(9, getV() + 1));
          })
      }
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  baselineSheetBuilder() {
    BaselinePickerSheet({
      candidates: this.baselineCandidates,
      houseName: this.pendingHouseName,
      onConfirm: (baselineId: number) => {
        this.confirmBaseline(baselineId);
      },
      onCancel: () => {
        this.showBaselineSheet = false;
      }
    })
  }

  private canStart(): boolean {
    if (this.selectedHouseId > 0) {
      return true;
    }
    return this.showForm && this.houseName.trim().length > 0;
  }

  private loadHouses(): void {
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new HouseRepo(uiCtx).listAll().then((list: House[]) => {
      this.houses = list;
    });
  }

  /** 编辑模式：已有档案回填表单（保留原实体，避免表单外字段被重置）。 */
  private loadForEdit(): void {
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    new HouseRepo(uiCtx).getById(this.editHouseId).then((h: House | null) => {
      if (h === null) {
        this.errorText = '房屋档案不存在，可能已被删除';
        return;
      }
      this.editingHouse = h;
      this.houseName = h.name;
      this.fullAddress = h.fullAddress;
      this.landlordName = h.landlordName;
      this.landlordPhone = h.landlordPhone;
      this.tenantName = h.tenantName;
      this.tenantPhone = h.tenantPhone;
      this.recordLocation = h.recordLocation;
      try {
        const spec = LayoutUtil.parse(h.layout);
        this.bedrooms = spec.bedrooms;
        this.livingRooms = spec.livingRooms;
        this.bathrooms = spec.bathrooms;
        this.balconies = spec.balconies;
      } catch (err) {
        // 户型格式异常时保持默认值
      }
    });
  }

  /** 编辑模式保存：更新档案后返回房屋详情页。 */
  private async saveEdit(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorText = '';
    try {
      const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const house = this.editingHouse;
      house.name = this.houseName.trim();
      house.layout = LayoutUtil.format(
        new LayoutSpec(this.bedrooms, this.livingRooms, this.bathrooms, this.balconies));
      house.fullAddress = this.fullAddress.trim();
      house.landlordName = this.landlordName.trim();
      house.landlordPhone = this.landlordPhone.trim();
      house.tenantName = this.tenantName.trim();
      house.tenantPhone = this.tenantPhone.trim();
      house.recordLocation = this.recordLocation;
      await new HouseRepo(uiCtx).update(house);
      this.getUIContext().getPromptAction().showToast({ message: '档案已保存' });
      this.pathStack.pop();
    } catch (err) {
      const e = err as Error;
      this.errorText = e.message;
    } finally {
      this.busy = false;
    }
  }

  private async start(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorText = '';
    try {
      const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      let houseId = this.selectedHouseId;
      let houseName = '';
      if (houseId <= 0) {
        const house = new House();
        house.name = this.houseName.trim();
        house.layout = LayoutUtil.format(new LayoutSpec(this.bedrooms, this.livingRooms, this.bathrooms, this.balconies));
        house.fullAddress = this.fullAddress.trim();
        house.landlordName = this.landlordName.trim();
        house.landlordPhone = this.landlordPhone.trim();
        house.tenantName = this.tenantName.trim();
        house.tenantPhone = this.tenantPhone.trim();
        house.recordLocation = this.recordLocation;
        houseId = await new HouseRepo(uiCtx).create(house);
        houseName = house.name;
        // F4：首次建档一次性提示（偏好读写失败静默，不阻塞检查流程）
        await this.maybeShowCreateHint(uiCtx);
      } else {
        for (const h of this.houses) {
          if (h.id === houseId) {
            houseName = h.name;
          }
        }
      }
      // E1：退租场景且已有基线候选时，先弹基线选择再创建会话
      if (this.sceneKey === SceneKey.MOVE_OUT) {
        const candidates = await InspectionLauncher.listBaselines(uiCtx, houseId);
        if (candidates.length > 0) {
          this.pendingHouseId = houseId;
          this.pendingHouseName = houseName;
          this.baselineCandidates = candidates;
          this.showBaselineSheet = true;
          return;
        }
      }
      await InspectionLauncher.startForHouse(uiCtx, this.pathStack, houseId, this.sceneKey, true);
    } catch (err) {
      const e = err as Error;
      this.errorText = e.message;
    } finally {
      this.busy = false;
    }
  }

  /** F4：首次新建房屋档案后弹一次性引导（已展示过则跳过）。 */
  private async maybeShowCreateHint(uiCtx: common.UIAbilityContext): Promise<void> {
    try {
      const shown = await AppPreferences.getBool(uiCtx, KEY_HOUSE_CREATE_HINT_SHOWN, false);
      if (shown) {
        return;
      }
      this.getUIContext().showAlertDialog({
        title: '房屋档案已创建',
        message: '档案信息可随时补充修改；建议完成一次入住检查并冻结，形成基线报告，方便日后对比与留证。',
        autoCancel: true,
        alignment: DialogAlignment.Center,
        confirm: {
          value: '我知道了',
          action: () => {
            AppPreferences.setBool(uiCtx, KEY_HOUSE_CREATE_HINT_SHOWN, true).catch(() => {
            });
          }
        }
      });
    } catch (err) {
      // 偏好读取失败时跳过提示
    }
  }

  private confirmBaseline(baselineId: number): void {
    this.showBaselineSheet = false;
    this.busy = true;
    const uiCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    InspectionLauncher.startForHouse(uiCtx, this.pathStack, this.pendingHouseId, this.sceneKey, true, baselineId)
      .catch((err: Error) => {
        this.errorText = err.message;
      })
      .then(() => {
        this.busy = false;
      });
  }
}
