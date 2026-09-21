// Theme.ets — 智宠管家 UI 主题常量
// 只用于 UI 层，不影响任何业务逻辑/接口/数据传输

export class Theme {
  // ── 主色：暖橙治愈系 ──
  static readonly PRIMARY: string = '#FF8C42'
  static readonly PRIMARY_DARK: string = '#E67630'
  static readonly PRIMARY_LIGHT: string = '#FFB380'
  static readonly PRIMARY_SOFT: string = '#FFF4EA'

  // ── 语义色 ──
  static readonly SUCCESS: string = '#3EC6A0'   // 薄荷绿（健康/正常）
  static readonly INFO: string = '#4D96FF'      // 天蓝（信息）
  static readonly WARNING: string = '#FF9800'   // 橙（警觉/偏高）
  static readonly DANGER: string = '#FF4D4F'    // 朱红（焦虑/告警）

  // ── 背景 ──
  static readonly BG: string = '#FBF7F2'         // 暖白
  static readonly BG_GRADIENT_START: string = '#FBF7F2'
  static readonly BG_GRADIENT_END: string = '#FFF4EA'
  static readonly CARD: string = '#FFFFFF'
  static readonly CARD_SOFT: string = '#FDF8F3'

  // ── 文字 ──
  static readonly TEXT_PRIMARY: string = '#1A1A1A'
  static readonly TEXT_SECONDARY: string = '#666666'
  static readonly TEXT_TERTIARY: string = '#999999'
  static readonly TEXT_WHITE: string = '#FFFFFF'

  // ── 边框/分割 ──
  static readonly BORDER: string = '#F0EBE5'
  static readonly DIVIDER: string = '#EFEAE4'

  // ── 圆角 ──
  static readonly RADIUS_SM: number = 12
  static readonly RADIUS_MD: number = 16
  static readonly RADIUS_LG: number = 20
  static readonly RADIUS_XL: number = 28
  static readonly RADIUS_PILL: number = 999
}

// 情绪 → 颜色映射（焦虑指数 0-100）
export function anxietyColor(level: number): string {
  if (level >= 61) return Theme.DANGER
  if (level >= 36) return Theme.WARNING
  if (level >= 16) return Theme.INFO
  return Theme.SUCCESS
}

// 情绪 → 中文标签
export function emotionLabel(emotion: string): string {
  switch (emotion) {
    case 'HAPPY': return '高兴'
    case 'CALM': return '平静'
    case 'ALERT': return '警觉'
    case 'ANXIOUS': return '焦虑'
    default: return emotion
  }
}
