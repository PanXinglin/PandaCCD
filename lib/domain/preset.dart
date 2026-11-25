import 'dart:convert';

const parameterLabels = {
  'strength': '预设强度',
  'grain': '噪点颗粒',
  'tint': '青红色偏',
  'saturation': '饱和度',
  'contrast': '对比度',
  'vignette': '镜头暗角',
  'bloom': '高光溢出',
  'steps': '色彩断层',
  'brightness': '亮度',
  'pixel': '像素低清',
  'beauty': '美颜总强度',
  'beautySmooth': '磨皮',
  'beautyEven': '匀肤去暗沉',
  'beautyWhiten': '肤色提亮',
  'faceSlim': '下颌瘦脸',
};
const parameterDefaults = <String, double>{
  'strength': 1,
  'grain': .18,
  'tint': .5,
  'saturation': .5,
  'contrast': .5,
  'vignette': .2,
  'bloom': .15,
  'steps': 0,
  'brightness': .5,
  'pixel': 0,
  'beauty': 0,
  'beautySmooth': .7,
  'beautyEven': .45,
  'beautyWhiten': .3,
  'faceSlim': 0,
};

class CcdPreset {
  final String id, name, subtitle, lut;
  final Map<String, double> values;
  final String? cameraName, sensor, description, scene;
  final int? year;
  final int swatch;
  const CcdPreset(
    this.id,
    this.name,
    this.subtitle,
    this.lut,
    this.values, {
    this.cameraName,
    this.year,
    this.sensor,
    this.description,
    this.scene,
    this.swatch = 0xffbed6c8,
  });
  bool get isCamera => cameraName != null;
  String get compactName =>
      isCamera ? name.replaceFirst(RegExp(r'^(佳能|索尼|富士) '), '') : name;
  String get stampLabel =>
      isCamera ? '${id.toUpperCase()} INSPIRED' : id.toUpperCase();
  Map<String, double> get parameters => {...parameterDefaults, ...values};
}

// Never reuse these IDs for model looks: existing recipes and photos keep their
// original creative styles. Old selected indices are migrated through this list.
const legacyPresetIds = ['jade', 'amber', 'moon', 'peach', 'pixel'];
const creativePresets = [
  CcdPreset('jade', '竹影青', '青绿清透 · 创意', 'jade', {
    'grain': .15,
    'vignette': .18,
  }, swatch: 0xffbed6c8),
  CcdPreset('amber', '落日罐头', '暖色浓郁 · 创意', 'amber', {
    'grain': .35,
    'bloom': .35,
    'contrast': .62,
  }, swatch: 0xffe9b079),
  CcdPreset('moon', '蓝调散步', '冷蓝夜色 · 创意', 'moon', {
    'grain': .25,
    'vignette': .35,
    'tint': .58,
  }, swatch: 0xffaab5d9),
  CcdPreset('peach', '桃气假日', '暖色柔和 · 创意', 'peach', {
    'grain': .1,
    'bloom': .2,
    'contrast': .43,
  }, swatch: 0xffe9bab5),
  CcdPreset('pixel', '像素日记', '低清断层 · 创意', 'pixel', {
    'grain': .48,
    'steps': .65,
    'pixel': .55,
  }, swatch: 0xffc9c4aa),
];

const presets = [
  CcdPreset(
    'g12',
    '佳能 G12',
    '自然肤色 · 通透日常',
    'g12',
    {
      'grain': .07,
      'vignette': .08,
      'bloom': .08,
      'contrast': .51,
      'saturation': .51,
    },
    cameraName: 'Canon PowerShot G12',
    year: 2010,
    sensor: '1/1.7英寸 CCD',
    swatch: 0xffcbbb9c,
    description: '轻微增强蓝天与红橙色，保留肤色和中间调层次；颗粒和高光溢出都较克制。',
    scene: '日常人像、旅行、晴天街拍',
  ),
  CcdPreset(
    'ixus95',
    '佳能 IXUS 95 IS',
    '暖肤柔光 · 晴日人像',
    'ixus95',
    {
      'grain': .12,
      'vignette': .1,
      'bloom': .15,
      'contrast': .47,
      'brightness': .52,
    },
    cameraName: 'Canon Digital IXUS 95 IS',
    year: 2009,
    sensor: '1/2.3英寸 CCD',
    swatch: 0xffe2bc9e,
    description: '日光暖肤的创作取向，亮部柔和、阴影稍抬，保留蓝绿颜色层次。',
    scene: '晴天人像、校园、午后咖啡馆',
  ),
  CcdPreset(
    'ixus130',
    '佳能 IXUS 130',
    '清透偏粉 · 闪光人像',
    'ixus130',
    {
      'grain': .09,
      'vignette': .08,
      'bloom': .12,
      'contrast': .46,
      'brightness': .53,
    },
    cameraName: 'Canon Digital IXUS 130 / SD1400 IS',
    year: 2010,
    sensor: '1/2.3英寸 CCD',
    swatch: 0xffd9bed2,
    description: '轻微粉紫与明亮中间调，呈现清透人像。闪光灯需另行开启。',
    scene: '人像自拍、室内聚会；可配合实体闪光灯',
  ),
  CcdPreset(
    'w350',
    '索尼 W350',
    '蓝绿清爽 · 街头风景',
    'w350',
    {
      'grain': .13,
      'vignette': .12,
      'bloom': .08,
      'contrast': .56,
      'saturation': .53,
    },
    cameraName: 'Sony Cyber-shot DSC-W350',
    year: 2010,
    sensor: '1/2.3英寸 Super HAD CCD',
    swatch: 0xffa9cbd4,
    description: '以清爽蓝绿呈现日光场景，色彩略有力度，中间调保持清晰。',
    scene: '城市街头、蓝天、绿植、水边',
  ),
  CcdPreset(
    'w830',
    '索尼 W830',
    '明亮柔和 · 轻盈日常',
    'w830',
    {
      'grain': .06,
      'vignette': .06,
      'bloom': .1,
      'contrast': .44,
      'brightness': .54,
      'saturation': .48,
    },
    cameraName: 'Sony Cyber-shot DSC-W830',
    year: 2014,
    sensor: '1/2.3英寸 Super HAD CCD',
    swatch: 0xffc4d9e1,
    description: '提亮中间调、降低反差，保留自然肤色与轻颗粒。',
    scene: '日常人像、明亮室内、随手记录',
  ),
  CcdPreset(
    'f200exr',
    '富士 F200EXR',
    '浓郁蓝绿 · VIVID灵感',
    'f200exr',
    {
      'grain': .1,
      'vignette': .1,
      'bloom': .05,
      'contrast': .56,
      'saturation': .55,
    },
    cameraName: 'Fujifilm FinePix F200EXR',
    year: 2009,
    sensor: '1/1.6英寸 Super CCD EXR',
    swatch: 0xff9db9a0,
    description: '参考VIVID模式方向，以较高饱和度和对比强化自然风景，蓝绿更浓郁。',
    scene: '绿植、山水、旅行风景',
  ),
  ...creativePresets,
];

int presetIndexFromSettings(Map<String, dynamic> settings) {
  final id = settings['selectedId'];
  if (id is String) {
    final index = presets.indexWhere((p) => p.id == id);
    if (index >= 0) return index;
  }
  final old = settings['selected'];
  if (old is int && old >= 0 && old < legacyPresetIds.length) {
    return presets.indexWhere((p) => p.id == legacyPresetIds[old]);
  }
  return 0;
}

class Recipe {
  final String presetId;
  final Map<String, double> values;
  // Portable embedded HALD; no machine-specific paths in recipes.
  final String? hald;
  const Recipe(this.presetId, this.values, {this.hald});
  String encode() => jsonEncode({
    'version': 1,
    'preset': presetId,
    'parameters': values,
    if (hald != null) 'haldPng': hald,
  });
  static Recipe decode(String source) {
    if (source.length > 24 * 1024 * 1024) throw const FormatException('预设文件过大');
    final data = jsonDecode(source);
    if (data is! Map ||
        data['version'] != 1 ||
        !presets.any((p) => p.id == data['preset']) ||
        data['parameters'] is! Map) {
      throw const FormatException('不支持的预设文件');
    }
    final values = Map<String, double>.from(parameterDefaults);
    for (final entry in (data['parameters'] as Map).entries) {
      if (!values.containsKey(entry.key) || entry.value is! num) {
        throw const FormatException('参数无效');
      }
      final value = (entry.value as num).toDouble();
      if (!value.isFinite || value < 0 || value > 1) {
        throw const FormatException('参数须在 0–1 之间');
      }
      values[entry.key as String] = value;
    }
    final hald = data['haldPng'];
    if (hald != null && hald is! String) {
      throw const FormatException('LUT 数据无效');
    }
    return Recipe(data['preset'] as String, values, hald: hald as String?);
  }
}

class Watermark {
  bool date = true, model = true, left = false, red = false, top = false;
  String text = '';
  bool includeModel = true;
  Map<String, dynamic> toJson() => {
    'date': date,
    'model': model,
    'left': left,
    'red': red,
    'top': top,
    'text': text,
    'includeModel': includeModel,
  };
  void restore(Map data) {
    date = data['date'] == true;
    model = data['model'] == true;
    left = data['left'] == true;
    red = data['red'] == true;
    top = data['top'] == true;
    text = cleanWatermarkText(
      data['text'] is String ? data['text'] as String : '',
    );
    includeModel = data['includeModel'] != false;
  }
}

String cleanWatermarkText(String value) => String.fromCharCodes(
  value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim().runes.take(32),
);

String watermarkLabel(Watermark stamp, String model) =>
    '${stamp.text.isEmpty ? 'PandaCCD' : stamp.text}'
    '${stamp.includeModel ? ' / ${model.toUpperCase()}' : ''}';
