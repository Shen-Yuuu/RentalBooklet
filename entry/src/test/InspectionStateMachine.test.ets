import { describe, it, expect } from '@ohos/hypium';
import { InspectionStatus } from '../main/ets/domain/model/CoreEnums';
import { InspectionStateMachine, StateTransitionError } from '../main/ets/domain/statemachine/InspectionStateMachine';

export default function inspectionStateMachineTest(): void {
  describe('InspectionStateMachine', () => {
    it('draft_can_freeze', 0, () => {
      expect(InspectionStateMachine.canTransition(InspectionStatus.DRAFT, InspectionStatus.FROZEN)).assertTrue();
    });

    it('frozen_only_to_revision_draft', 0, () => {
      expect(InspectionStateMachine.canTransition(InspectionStatus.FROZEN, InspectionStatus.DRAFT)).assertTrue();
      expect(InspectionStateMachine.canTransition(InspectionStatus.FROZEN, InspectionStatus.FROZEN)).assertFalse();
    });

    it('draft_cannot_self_transition', 0, () => {
      expect(InspectionStateMachine.canTransition(InspectionStatus.DRAFT, InspectionStatus.DRAFT)).assertFalse();
    });

    it('assert_throws_on_illegal', 0, () => {
      let threw = false;
      try {
        InspectionStateMachine.assertTransition(InspectionStatus.FROZEN, InspectionStatus.FROZEN);
      } catch (e) {
        threw = e instanceof StateTransitionError;
      }
      expect(threw).assertTrue();
    });
  });
}
