import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit';
import { WidgetService } from '../../infra/widget/WidgetService';

/**
 * 检查进度卡片扩展（F1）：
 * - onAddForm 同步返回占位数据（卡点：onAddForm 不能等待异步查询），
 *   随后异步解析目标检查 → 绑定 → updateForm 推送真实进度；
 * - onUpdateForm 兜底按绑定刷新（updateEnabled=false 时通常不触发）；
 * - onRemoveForm 解除绑定（进程内文件操作，静默容错在 WidgetService 内部保证）。
 */
export default class FormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const data: Record<string, Object> = {
      'houseName': '租房留证册',
      'sceneTitle': '',
      'progressText': '正在读取检查进度…',
      'statusText': '',
      'inspectionId': 0
    };
    let formId = '';
    try {
      const raw = want.parameters?.[formInfo.FormParam.IDENTITY_KEY];
      if (raw !== undefined && raw !== null) {
        formId = `${raw}`;
      }
    } catch (err) {
      formId = '';
    }
    if (formId.length > 0) {
      WidgetService.onFormAdded(this.context, formId);
    }
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    const bindings = WidgetService.loadBindings(this.context);
    for (const b of bindings) {
      if (b.formId === formId) {
        WidgetService.updateCard(this.context, b.formId, b.inspectionId).catch(() => {
        });
      }
    }
  }

  onRemoveForm(formId: string): void {
    WidgetService.unbindForm(this.context, formId);
  }

  onCastToNormalForm(formId: string): void {
    // 临时卡片转常态：绑定关系不变，无需处理
  }
}
