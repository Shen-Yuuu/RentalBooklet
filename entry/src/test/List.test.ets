import compareAlignerTest from './CompareAligner.test';
import completenessEngineTest from './CompletenessEngine.test';
import inspectionStateMachineTest from './InspectionStateMachine.test';
import layoutUtilTest from './LayoutUtil.test';
import localUnitTest from './LocalUnit.test';
import manifestBuilderTest from './ManifestBuilder.test';
import ocrCandidateFilterTest from './OcrCandidateFilter.test';
import permissionSpecTest from './PermissionSpec.test';
import qualityHeuristicsTest from './QualityHeuristics.test';
import reportComposerTest from './ReportComposer.test';
import sizeFormatTest from './SizeFormat.test';
import templateEngineTest from './TemplateEngine.test';
import textLineBreakerTest from './TextLineBreaker.test';
import textRefinerTest from './TextRefiner.test';

export default function testsuite(): void {
  localUnitTest();
  templateEngineTest();
  layoutUtilTest();
  permissionSpecTest();
  inspectionStateMachineTest();
  textRefinerTest();
  qualityHeuristicsTest();
  ocrCandidateFilterTest();
  completenessEngineTest();
  manifestBuilderTest();
  textLineBreakerTest();
  reportComposerTest();
  compareAlignerTest();
  sizeFormatTest();
}
