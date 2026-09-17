import { MeterType } from '../model/CoreEnums';
import { GuideType, SceneTemplate } from '../model/TemplateModels';

/**
 * 内置场景模板（产品文档 §3.2 的内容基线）。
 * 约束：move_out 与 move_in 的房间/检查项 key 必须完全一致，前后对比按 key 对齐。
 */
export const MOVE_IN_TEMPLATE: SceneTemplate = {
  sceneKey: 'move_in',
  title: '入住验房',
  description: '按房间路线完成入住前的房屋状况检查',
  rooms: [
    {
      key: 'entrance', name: '入户门', items: [
        { key: 'door_appearance', name: '门体外观（划痕/凹陷）' },
        { key: 'door_lock', name: '门锁与把手开合' },
        { key: 'peephole', name: '猫眼', required: false },
        { key: 'doorbell', name: '门铃', required: false },
        { key: 'door_seal', name: '密封条', required: false },
        { key: 'entrance_floor', name: '门口地面', required: false }
      ]
    },
    {
      key: 'living', name: '客厅', items: [
        { key: 'wall', name: '墙面（污渍/裂缝/水渍）' },
        { key: 'ceiling', name: '天花板与吊顶', required: false },
        { key: 'floor', name: '地板/瓷砖（划痕/空鼓）' },
        { key: 'window', name: '窗户与纱窗' },
        { key: 'curtain', name: '窗帘及轨道', required: false },
        { key: 'light', name: '灯具与开关', required: false },
        { key: 'socket', name: '插座通电', required: false },
        { key: 'ac', name: '空调外观与运行', required: false }
      ]
    },
    {
      key: 'balcony', name: '阳台', items: [
        { key: 'floor_drain', name: '地面与排水口', required: false },
        { key: 'railing', name: '栏杆稳固', required: false },
        { key: 'dryer_rack', name: '晾衣设施', required: false },
        { key: 'washer_spot', name: '洗衣机位（若在此）', required: false }
      ]
    },
    {
      key: 'kitchen', name: '厨房', items: [
        { key: 'cabinet', name: '橱柜门板与铰链' },
        { key: 'countertop', name: '台面（划痕/烫痕）' },
        { key: 'faucet_drain', name: '水龙头与下水' },
        { key: 'gas_stove', name: '燃气灶' },
        { key: 'range_hood', name: '油烟机', required: false },
        { key: 'gas_valve', name: '燃气阀门', required: false },
        { key: 'wall_tile', name: '墙面瓷砖', required: false },
        { key: 'floor_drain', name: '地漏', required: false }
      ]
    },
    {
      key: 'bathroom', name: '卫生间', items: [
        { key: 'toilet', name: '马桶（冲水/底座密封）' },
        { key: 'sink', name: '洗手台与下水' },
        { key: 'shower', name: '淋浴区（花洒/挡水条）', required: false },
        { key: 'mirror_cabinet', name: '镜柜', required: false },
        { key: 'exhaust_fan', name: '排风扇', required: false },
        { key: 'floor_drain', name: '地漏排水' },
        { key: 'leak_traces', name: '渗漏痕迹', required: false },
        { key: 'wall_tile', name: '瓷砖空鼓', required: false }
      ]
    },
    {
      key: 'master_bedroom', name: '主卧', items: [
        { key: 'wall', name: '墙面' },
        { key: 'floor', name: '地板', required: false },
        { key: 'window_lock', name: '窗户与锁扣' },
        { key: 'wardrobe', name: '衣柜（门/隔板/抽屉）', required: false },
        { key: 'ac', name: '空调', required: false },
        { key: 'curtain', name: '窗帘', required: false },
        { key: 'socket', name: '插座', required: false }
      ]
    },
    {
      key: 'second_bedroom', name: '次卧', items: [
        { key: 'wall', name: '墙面' },
        { key: 'floor', name: '地板', required: false },
        { key: 'window_lock', name: '窗户与锁扣' },
        { key: 'wardrobe', name: '衣柜（门/隔板/抽屉）', required: false },
        { key: 'ac', name: '空调', required: false },
        { key: 'curtain', name: '窗帘', required: false },
        { key: 'socket', name: '插座', required: false }
      ]
    },
    {
      key: 'meters', name: '水电燃气表', items: [
        { key: 'electricity_meter', name: '电表读数', guide: GuideType.DIAL },
        { key: 'water_meter', name: '水表读数', guide: GuideType.DIAL },
        { key: 'gas_meter', name: '燃气表读数', guide: GuideType.DIAL },
        { key: 'meter_id', name: '表具编号与安装位置', required: false }
      ]
    },
    {
      key: 'handover', name: '钥匙与门禁', items: [
        { key: 'key_count', name: '钥匙数量' },
        { key: 'access_card_count', name: '门禁卡数量' },
        { key: 'parking_or_storage', name: '车位/储物凭证', required: false }
      ]
    }
  ],
  meters: [MeterType.ELECTRICITY, MeterType.WATER, MeterType.GAS],
  handover: true
};

/** 退租与入住同构（key 一致），前后对比按 key 对齐。 */
export const MOVE_OUT_TEMPLATE: SceneTemplate = {
  sceneKey: 'move_out',
  title: '退租交房',
  description: '复用入住结构逐项核对，生成退租交接报告',
  rooms: MOVE_IN_TEMPLATE.rooms,
  meters: MOVE_IN_TEMPLATE.meters,
  handover: true
};

export const REPAIR_TEMPLATE: SceneTemplate = {
  sceneKey: 'repair',
  title: '中途维修',
  description: '记录维修前中后的关键信息与凭证',
  rooms: [
    {
      key: 'fault_spot', name: '故障位置', items: [
        { key: 'fault_overview', name: '故障位置全景照' },
        { key: 'fault_closeup', name: '故障对象近照' }
      ]
    },
    {
      key: 'fault_desc', name: '故障描述', items: [
        { key: 'fault_note', name: '问题描述' },
        { key: 'fault_detail', name: '故障细节照' }
      ]
    },
    {
      key: 'repairer', name: '维修人员与时间', items: [
        { key: 'repairer_info', name: '维修人员/单位' },
        { key: 'visit_time', name: '上门时间' }
      ]
    },
    {
      key: 'parts', name: '更换零件', items: [
        { key: 'parts_list', name: '更换零件清单', required: false },
        { key: 'parts_photo', name: '零件照片', required: false }
      ]
    },
    {
      key: 'cost', name: '费用凭证', items: [
        { key: 'cost_amount', name: '费用金额', required: false },
        { key: 'cost_receipt', name: '凭证照片', required: false }
      ]
    },
    {
      key: 'after_check', name: '维修后运行', items: [
        { key: 'run_status', name: '运行状态确认' },
        { key: 'after_photo', name: '维修后照片' }
      ]
    }
  ],
  meters: [],
  handover: false
};

export const CLEANING_TEMPLATE: SceneTemplate = {
  sceneKey: 'cleaning',
  title: '家政保洁',
  description: '保洁前后对照留痕',
  rooms: [
    {
      key: 'overview', name: '全屋概览', items: [
        { key: 'before_overview', name: '保洁前全屋概览照' }
      ]
    },
    {
      key: 'kitchen', name: '厨房', items: [
        { key: 'before_panorama', name: '保洁前厨房全景' },
        { key: 'stain_detail', name: '重点污渍细节' }
      ]
    },
    {
      key: 'bathroom', name: '卫生间', items: [
        { key: 'before_panorama', name: '保洁前卫生间全景' },
        { key: 'stain_detail', name: '重点污渍细节' }
      ]
    },
    {
      key: 'living', name: '客厅', items: [
        { key: 'before_panorama', name: '保洁前客厅全景' },
        { key: 'stain_detail', name: '重点污渍细节' }
      ]
    },
    {
      key: 'finish', name: '收尾核验', items: [
        { key: 'after_compare', name: '保洁后同角度对照照' },
        { key: 'finish_confirm', name: '保洁完成确认' }
      ]
    }
  ],
  meters: [],
  handover: false
};

export const APPLIANCE_TEMPLATE: SceneTemplate = {
  sceneKey: 'appliance',
  title: '家电交付',
  description: '逐台登记家电型号、序列号与通电状态',
  rooms: [
    {
      key: 'fridge', name: '冰箱', items: [
        { key: 'appearance', name: '外观检查' },
        { key: 'model_serial', name: '型号与序列号' },
        { key: 'power_on', name: '通电运行' },
        { key: 'accessories', name: '附件与说明书', required: false }
      ]
    },
    {
      key: 'ac', name: '空调', items: [
        { key: 'appearance', name: '外观检查' },
        { key: 'model_serial', name: '型号与序列号' },
        { key: 'power_on', name: '通电运行' },
        { key: 'accessories', name: '附件与说明书', required: false }
      ]
    },
    {
      key: 'washer', name: '洗衣机', items: [
        { key: 'appearance', name: '外观检查' },
        { key: 'model_serial', name: '型号与序列号' },
        { key: 'power_on', name: '通电运行' },
        { key: 'accessories', name: '附件与说明书', required: false }
      ]
    },
    {
      key: 'gas_stove', name: '燃气灶', items: [
        { key: 'appearance', name: '外观检查' },
        { key: 'model_serial', name: '型号与序列号' },
        { key: 'power_on', name: '点火运行' },
        { key: 'accessories', name: '附件与说明书', required: false }
      ]
    },
    {
      key: 'other_appliance', name: '其他家电', items: [
        { key: 'appearance', name: '设备名称与外观' },
        { key: 'model_serial', name: '型号与序列号' },
        { key: 'power_on', name: '通电运行' },
        { key: 'accessories', name: '附件与说明书', required: false }
      ]
    }
  ],
  meters: [],
  handover: false
};

export const CUSTOM_TEMPLATE: SceneTemplate = {
  sceneKey: 'custom',
  title: '自定义检查',
  description: '从模板库勾选房间与项目',
  rooms: [
    {
      key: 'custom_room', name: '自定义房间', items: [
        { key: 'custom_item', name: '自定义检查项', required: false }
      ]
    }
  ],
  meters: [],
  handover: false
};

export const BUILTIN_TEMPLATES: SceneTemplate[] = [
  MOVE_IN_TEMPLATE,
  MOVE_OUT_TEMPLATE,
  REPAIR_TEMPLATE,
  CLEANING_TEMPLATE,
  APPLIANCE_TEMPLATE,
  CUSTOM_TEMPLATE
];
