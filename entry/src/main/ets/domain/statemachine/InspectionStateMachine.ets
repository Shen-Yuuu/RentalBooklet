import { InspectionStatus } from '../model/CoreEnums';

export class StateTransitionError extends Error {
  constructor(message: string) {
    super(message);
  }
}

/**
 * 检查记录状态机：DRAFT ⇄ FROZEN。
 * 约束：FROZEN 记录本体不可变写；FROZEN→DRAFT 仅用于"创建修订版本"（生成新 DRAFT 记录）的语义。
 */
export class InspectionStateMachine {
  static canTransition(from: InspectionStatus, to: InspectionStatus): boolean {
    if (from === InspectionStatus.DRAFT) {
      return to === InspectionStatus.FROZEN;
    }
    if (from === InspectionStatus.FROZEN) {
      return to === InspectionStatus.DRAFT;
    }
    return false;
  }

  static assertTransition(from: InspectionStatus, to: InspectionStatus): void {
    if (!InspectionStateMachine.canTransition(from, to)) {
      throw new StateTransitionError(`非法状态转换: ${from} → ${to}`);
    }
  }
}
