import { describe, it, expect } from '@ohos/hypium';
import {
  ManifestSummaryRow, PdfDocModel, PdfTextLine, ReportCompareRow, ReportComposer,
  ReportInput, ReportIssue, ReportItem, ReportMeter, ReportParticipant, ReportPhotoRef,
  ReportRoom
} from '../main/ets/domain/report/ReportComposer';
import { MeasureFn } from '../main/ets/domain/report/TextLineBreaker';
import { ManifestBuilder } from '../main/ets/domain/manifest/ManifestBuilder';

function makeCompareRow(room: string, item: string, result: string): ReportCompareRow {
  const row = new ReportCompareRow();
  row.room = room;
  row.item = item;
  row.result = result;
  return row;
}

function makePhotoRef(thumbPath: string, noText: string, imported: boolean): ReportPhotoRef {
  const ref = new ReportPhotoRef();
  ref.thumbPath = thumbPath;
  ref.noText = noText;
  ref.imported = imported;
  return ref;
}

function makeItem(name: string, status: string, note: string): ReportItem {
  const item = new ReportItem();
  item.name = name;
  item.status = status;
  item.noteFinal = note;
  return item;
}

function makeParticipant(roleText: string, name: string): ReportParticipant {
  const p = new ReportParticipant();
  p.roleText = roleText;
  p.name = name;
  return p;
}

function makeRoom(name: string, items: ReportItem[], panoramaThumb: string): ReportRoom {
  const room = new ReportRoom();
  room.name = name;
  room.items = items;
  if (panoramaThumb.length > 0) {
    room.panoramaRefs.push(makePhotoRef(panoramaThumb, '图 1', false));
  }
  return room;
}

function makeInput(): ReportInput {
  const input = new ReportInput();
  input.houseName = '阳光小区 3-502';
  input.fullAddress = '幸福市幸福区幸福路 1 号 3-502';
  input.includeFullAddress = false;
  input.sceneTitle = '入住检查';
  input.reportNo = 'RB-20260915-0001';
  input.frozenAtText = '2026-09-15 14:30';
  input.participantsText = '房东：张三　租客：李四';
  input.participants.push(makeParticipant('房东', '张三'));
  input.participants.push(makeParticipant('租客', '李四'));
  input.confirmedAtText = '2026-09-15 14:30';
  input.extraNote = '交房时燃气已抄表，双方现场确认。';
  input.requiredRateText = '92%';
  input.suggestedRateText = '75%';

  const sofa = makeItem('沙发', 'ISSUE', '扶手处有污渍，约 5 厘米');
  sofa.photoRefs.push(makePhotoRef('/files/insp/1/thumbs/102_t.jpg', '图 2', true));
  sofa.photoRefs.push(makePhotoRef('/files/insp/1/thumbs/103_t.jpg', '图 3', false));
  input.rooms.push(makeRoom('客厅', [makeItem('墙面', 'OK', ''), sofa],
    '/files/insp/1/thumbs/101_t.jpg'));
  input.rooms.push(makeRoom('主卧', [makeItem('窗户', 'OK', '左下角有旧裂纹')], ''));

  const issue = new ReportIssue();
  issue.room = '客厅';
  issue.item = '沙发';
  issue.note = '扶手处有污渍，约 5 厘米';
  issue.photoNos = '2、3';
  input.issueList.push(issue);

  const water = new ReportMeter();
  water.label = '水表';
  water.valueText = '1234';
  input.meters.push(water);
  const electric = new ReportMeter();
  electric.label = '电表';
  electric.valueText = '未登记';
  input.meters.push(electric);
  const gas = new ReportMeter();
  gas.label = '燃气表';
  gas.valueText = '无表具';
  input.meters.push(gas);

  input.handoverText = '钥匙 2 把 · 门禁卡 2 张';

  const row = new ManifestSummaryRow();
  row.fileName = '101.jpg';
  row.shaShort = '3b1f00e9a2c4';
  row.noText = '图 1';
  input.manifestSummary.push(row);

  return input;
}

/** 汇总全文档文本（便于"包含"断言）。 */
function allTexts(doc: PdfDocModel): string[] {
  const texts: string[] = [];
  for (const page of doc.pages) {
    for (const line of page.texts) {
      texts.push(line.text);
    }
  }
  return texts;
}

export default function reportComposerTest(): void {
  describe('ReportComposer', () => {
    it('compose_pages_at_least_six', 0, () => {
      const doc = ReportComposer.compose(makeInput());
      // 封面/交接数据/逐房间/问题汇总/确认信息/校验信息 各至少一页
      expect(doc.pages.length >= 6).assertTrue();
    });

    it('cover_contains_report_no_and_house', 0, () => {
      const doc = ReportComposer.compose(makeInput());
      const coverTexts: string[] = [];
      for (const line of doc.pages[0].texts) {
        coverTexts.push(line.text);
      }
      let hasReportNo = false;
      let hasHouse = false;
      for (const t of coverTexts) {
        if (t.includes('RB-20260915-0001')) {
          hasReportNo = true;
        }
        if (t.includes('阳光小区 3-502')) {
          hasHouse = true;
        }
      }
      expect(hasReportNo).assertTrue();
      expect(hasHouse).assertTrue();
    });

    it('full_address_hidden_by_default_shown_when_enabled', 0, () => {
      const hiddenDoc = ReportComposer.compose(makeInput());
      let hiddenHasAddress = false;
      for (const line of hiddenDoc.pages[0].texts) {
        if (line.text.includes('房屋地址')) {
          hiddenHasAddress = true;
        }
      }
      expect(hiddenHasAddress).assertFalse();

      const input = makeInput();
      input.includeFullAddress = true;
      const shownDoc = ReportComposer.compose(input);
      let shownHasAddress = false;
      for (const line of shownDoc.pages[0].texts) {
        if (line.text.includes('房屋地址：幸福市幸福区幸福路 1 号 3-502')) {
          shownHasAddress = true;
        }
      }
      expect(shownHasAddress).assertTrue();
    });

    it('issue_summary_rows_present', 0, () => {
      const doc = ReportComposer.compose(makeInput());
      const texts = allTexts(doc);
      let found = false;
      for (const t of texts) {
        if (t.includes('客厅 · 沙发') && t.includes('污渍')) {
          found = true;
        }
      }
      expect(found).assertTrue();
    });

    it('issue_row_appends_photo_nos', 0, () => {
      const doc = ReportComposer.compose(makeInput());
      const texts = allTexts(doc);
      let found = false;
      for (const t of texts) {
        if (t.includes('客厅 · 沙发') && t.includes('照片：2、3')) {
          found = true;
        }
      }
      expect(found).assertTrue();
    });

    it('unregistered_meter_fallback_text_present', 0, () => {
      const doc = ReportComposer.compose(makeInput());
      const texts = allTexts(doc);
      let hasUnregistered = false;
      let hasNa = false;
      for (const t of texts) {
        if (t.includes('电表：未登记')) {
          hasUnregistered = true;
        }
        if (t.includes('燃气表：无表具')) {
          hasNa = true;
        }
      }
      expect(hasUnregistered).assertTrue();
      expect(hasNa).assertTrue();
    });

    it('disclaimer_present_on_verify_page', 0, () => {
      const doc = ReportComposer.compose(makeInput());
      const lastPage = doc.pages[doc.pages.length - 1];
      let found = false;
      for (const line of lastPage.texts) {
        if (line.text === ManifestBuilder.DISCLAIMER) {
          found = true;
        }
      }
      expect(found).assertTrue();
    });

    it('verify_page_rows_carry_photo_no_prefix', 0, () => {
      const doc = ReportComposer.compose(makeInput());
      const texts = allTexts(doc);
      let found = false;
      for (const t of texts) {
        if (t === '图 1 · 101.jpg　3b1f00e9a2c4') {
          found = true;
        }
      }
      expect(found).assertTrue();
    });

    it('all_coords_within_page_bounds', 0, () => {
      const input = makeInput();
      // 大量问题行制造分页边界
      for (let i = 0; i < 80; i++) {
        const issue = new ReportIssue();
        issue.room = `房间${i}`;
        issue.item = `项目${i}`;
        issue.note = '这是一个用于撑满分页边界的长描述文本，检验坐标不越界';
        input.issueList.push(issue);
        const row = new ManifestSummaryRow();
        row.fileName = `photo_${i}.jpg`;
        row.shaShort = 'a1b2c3d4e5f6';
        input.manifestSummary.push(row);
      }
      const doc = ReportComposer.compose(input);
      expect(doc.pages.length > 6).assertTrue();
      for (const page of doc.pages) {
        for (const line of page.texts) {
          ReportComposerAssert.coordInRange(line);
        }
        for (const img of page.images) {
          expect(img.x >= 0 && img.x + img.w <= ReportComposer.PAGE_W).assertTrue();
          expect(img.y >= 0 && img.y + img.h <= ReportComposer.PAGE_H).assertTrue();
        }
      }
    });

    it('issue_summary_continuation_pages_carry_rows', 0, () => {
      const input = makeInput();
      for (let i = 0; i < 80; i++) {
        const issue = new ReportIssue();
        issue.room = `房间${i}`;
        issue.item = `项目${i}`;
        issue.note = '';
        input.issueList.push(issue);
      }
      const doc = ReportComposer.compose(input);
      let continuationPages = 0;
      let continuationPagesWithRows = 0;
      for (const page of doc.pages) {
        let hasContinuationTitle = false;
        let hasRow = false;
        for (const line of page.texts) {
          if (line.text === '问题汇总（续）') {
            hasContinuationTitle = true;
          }
          if (line.text.startsWith('房间') && line.text.includes(' · ')) {
            hasRow = true;
          }
        }
        if (hasContinuationTitle) {
          continuationPages++;
          if (hasRow) {
            continuationPagesWithRows++;
          }
        }
      }
      expect(continuationPages >= 1).assertTrue();
      expect(continuationPagesWithRows === continuationPages).assertTrue();
    });

    it('many_rooms_paginate_into_extra_pages', 0, () => {
      const input = makeInput();
      input.rooms = [];
      for (let i = 0; i < 15; i++) {
        const items: ReportItem[] = [];
        for (let j = 0; j < 8; j++) {
          items.push(makeItem(`项目${j}`, 'OK', ''));
        }
        input.rooms.push(makeRoom(`房间${i}`, items, '/files/insp/1/thumbs/t.jpg'));
      }
      const doc = ReportComposer.compose(input);
      // 每房间块约 340pt，一页仅能放 2 个房间 → 房间页 ≥ 8
      expect(doc.pages.length >= 5 + 8).assertTrue();
    });

    it('empty_issue_list_keeps_title', 0, () => {
      const input = makeInput();
      input.issueList = [];
      const doc = ReportComposer.compose(input);
      const texts = allTexts(doc);
      let hasTitle = false;
      let hasPlaceholder = false;
      for (const t of texts) {
        if (t === '问题汇总') {
          hasTitle = true;
        }
        if (t === '本次检查未登记问题项') {
          hasPlaceholder = true;
        }
      }
      expect(hasTitle).assertTrue();
      expect(hasPlaceholder).assertTrue();
    });

    it('panorama_thumb_referenced_as_image', 0, () => {
      const doc = ReportComposer.compose(makeInput());
      let found = false;
      for (const page of doc.pages) {
        for (const img of page.images) {
          if (img.path === '/files/insp/1/thumbs/101_t.jpg') {
            found = true;
          }
        }
      }
      expect(found).assertTrue();
    });

    it('panorama_caption_marks_imported', 0, () => {
      const input = makeInput();
      input.rooms[1].panoramaRefs.push(makePhotoRef('/files/insp/1/thumbs/201_t.jpg', '图 4', true));
      const doc = ReportComposer.compose(input);
      const texts = allTexts(doc);
      let found = false;
      for (const t of texts) {
        if (t === '全景 · 图 4 · 从相册导入') {
          found = true;
        }
      }
      expect(found).assertTrue();
    });

    it('photo_refs_rendered_as_thumbnails_with_captions', 0, () => {
      const doc = ReportComposer.compose(makeInput());
      let importedThumb = false;
      let capturedThumb = false;
      let importedCaption = false;
      let capturedCaption = false;
      for (const page of doc.pages) {
        for (const img of page.images) {
          if (img.path === '/files/insp/1/thumbs/102_t.jpg') {
            importedThumb = true;
          }
          if (img.path === '/files/insp/1/thumbs/103_t.jpg') {
            capturedThumb = true;
          }
        }
        for (const line of page.texts) {
          if (line.text === '图 2·从相册导入') {
            importedCaption = true;
          }
          if (line.text === '图 3') {
            capturedCaption = true;
          }
        }
      }
      expect(importedThumb).assertTrue();
      expect(capturedThumb).assertTrue();
      expect(importedCaption).assertTrue();
      expect(capturedCaption).assertTrue();
    });

    it('long_note_truncated_with_ellipsis', 0, () => {
      const input = makeInput();
      const longNote = '超长备注'.repeat(30); // 120 字符 > 46 截断阈值
      input.rooms[0].items[0].noteFinal = longNote;
      const doc = ReportComposer.compose(input);
      const texts = allTexts(doc);
      let found = false;
      for (const t of texts) {
        if (t.startsWith('墙面：正常——') && t.endsWith('…') && t.length < 20 + 46) {
          found = true;
        }
      }
      expect(found).assertTrue();
    });

    // ===== 确认信息页（产品文档 §5.5 第 5 页） =====

    it('confirm_page_renders_participants_and_time', 0, () => {
      const doc = ReportComposer.compose(makeInput());
      let pageIdx = -1;
      for (let i = 0; i < doc.pages.length; i++) {
        for (const line of doc.pages[i].texts) {
          if (line.text === '确认信息') {
            pageIdx = i;
          }
        }
      }
      expect(pageIdx >= 0).assertTrue();
      let landlord = false;
      let tenant = false;
      for (const line of doc.pages[pageIdx].texts) {
        if (line.text === '房东：张三　确认时间：2026-09-15 14:30') {
          landlord = true;
        }
        if (line.text === '租客：李四　确认时间：2026-09-15 14:30') {
          tenant = true;
        }
      }
      expect(landlord).assertTrue();
      expect(tenant).assertTrue();
    });

    it('confirm_page_empty_participants_placeholder', 0, () => {
      const input = makeInput();
      input.participants = [];
      const doc = ReportComposer.compose(input);
      const texts = allTexts(doc);
      let found = false;
      for (const t of texts) {
        if (t === '未填写参与人') {
          found = true;
        }
      }
      expect(found).assertTrue();
    });

    // ===== E3：前后对比结论页 =====

    it('compare_page_not_created_without_rows', 0, () => {
      const doc = ReportComposer.compose(makeInput());
      const texts = allTexts(doc);
      let hasTitle = false;
      for (const t of texts) {
        if (t.includes('前后对比结论')) {
          hasTitle = true;
        }
      }
      expect(hasTitle).assertFalse();
    });

    it('compare_page_renders_rows_and_marks_changed_red', 0, () => {
      const input = makeInput();
      input.compareRows.push(makeCompareRow('客厅', '墙面', '无变化'));
      input.compareRows.push(makeCompareRow('厨房', '冰箱', '有变化'));
      input.compareRows.push(makeCompareRow('主卧', '窗户', '待确认'));
      const doc = ReportComposer.compose(input);

      // 定位对比结论页
      let pageIdx = -1;
      for (let i = 0; i < doc.pages.length; i++) {
        for (const line of doc.pages[i].texts) {
          if (line.text === '前后对比结论') {
            pageIdx = i;
          }
        }
      }
      expect(pageIdx >= 0).assertTrue();
      const page = doc.pages[pageIdx];
      let unchangedColor = -1;
      let changedColor = -1;
      let changedBold = false;
      let pendingFound = false;
      let neutralHint = false;
      for (const line of page.texts) {
        if (line.text === '客厅 · 墙面：无变化') {
          unchangedColor = line.color;
        }
        if (line.text === '厨房 · 冰箱：有变化') {
          changedColor = line.color;
          changedBold = line.bold;
        }
        if (line.text === '主卧 · 窗户：待确认') {
          pendingFound = true;
        }
        if (line.text.includes('仅呈现登记内容，不代表责任归属')) {
          neutralHint = true;
        }
      }
      expect(unchangedColor).assertEqual(0);
      expect(changedColor).assertEqual(ReportComposer.RED);
      expect(changedBold).assertTrue();
      expect(pendingFound).assertTrue();
      expect(neutralHint).assertTrue();
    });

    it('page_order_issue_compare_confirm_verify', 0, () => {
      const input = makeInput();
      input.compareRows.push(makeCompareRow('客厅', '墙面', '无变化'));
      const doc = ReportComposer.compose(input);
      let issueIdx = -1;
      let compareIdx = -1;
      let confirmIdx = -1;
      let verifyIdx = -1;
      for (let i = 0; i < doc.pages.length; i++) {
        for (const line of doc.pages[i].texts) {
          if (line.text === '问题汇总' && issueIdx < 0) {
            issueIdx = i;
          }
          if (line.text === '前后对比结论' && compareIdx < 0) {
            compareIdx = i;
          }
          if (line.text === '确认信息' && confirmIdx < 0) {
            confirmIdx = i;
          }
          if (line.text === '文件校验信息' && verifyIdx < 0) {
            verifyIdx = i;
          }
        }
      }
      expect(compareIdx >= 0).assertTrue();
      expect(compareIdx > issueIdx).assertTrue();
      expect(confirmIdx > compareIdx).assertTrue();
      expect(verifyIdx > confirmIdx).assertTrue();
      // 免责文案仍在最后一页
      const lastPage = doc.pages[doc.pages.length - 1];
      let found = false;
      for (const line of lastPage.texts) {
        if (line.text === ManifestBuilder.DISCLAIMER) {
          found = true;
        }
      }
      expect(found).assertTrue();
    });

    it('compare_rows_paginate_with_coords_in_bounds', 0, () => {
      const input = makeInput();
      for (let i = 0; i < 60; i++) {
        input.compareRows.push(makeCompareRow(`房间${i}`, `项目${i}`, i % 2 === 0 ? '有变化' : '无变化'));
      }
      const doc = ReportComposer.compose(input);
      let comparePages = 0;
      for (const page of doc.pages) {
        let isCompare = false;
        for (const line of page.texts) {
          if (line.text.startsWith('前后对比结论')) {
            isCompare = true;
          }
          ReportComposerAssert.coordInRange(line);
        }
        if (isCompare) {
          comparePages++;
        }
      }
      // 60 行 + 标题/说明 → 至少 2 页
      expect(comparePages >= 2).assertTrue();
    });

    it('custom_measure_function_accepted', 0, () => {
      const customMeasure: MeasureFn = (text: string, fontSize: number): number => {
        return text.length * fontSize * 0.6;
      };
      const doc = ReportComposer.compose(makeInput(), customMeasure);
      expect(doc.pages.length >= 6).assertTrue();
    });
  });
}

/** 坐标版心断言辅助（test 内独立 class，避免污染主代码）。 */
class ReportComposerAssert {
  static coordInRange(line: PdfTextLine): void {
    expect(line.x >= 0 && line.x <= ReportComposer.PAGE_W).assertTrue();
    expect(line.y >= 0 && line.y <= ReportComposer.PAGE_H).assertTrue();
    expect(line.fontSize > 0).assertTrue();
  }
}
