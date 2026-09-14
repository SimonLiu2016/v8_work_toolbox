import 'dart:math';

/// 密码生成器（设计 D8）
///
/// - 随机模式：长度 8–128，字符集开关，每启用集至少一字符，Fisher-Yates 洗牌
/// - passphrase 模式：内置词表，词数/分隔符/数字后缀可选
/// - 熵源：Random.secure()
class PasswordGenerator {
  PasswordGenerator({Random? random}) : _random = random ?? Random.secure();

  static const int minLength = 8;
  static const int maxLength = 128;
  static const String ambiguousChars = 'Il1O0o';

  static const String _lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const String _uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _digits = '0123456789';
  static const String _symbols = r'!@#$%^&*()-_=+[]{};:,.<>?/~';

  final Random _random;

  /// 生成随机密码
  ///
  /// 至少启用一个字符集，否则抛 ArgumentError。
  String generate({
    int length = 20,
    bool useLowercase = true,
    bool useUppercase = true,
    bool useDigits = true,
    bool useSymbols = true,
    bool excludeAmbiguous = false,
  }) {
    if (length < minLength || length > maxLength) {
      throw ArgumentError('长度须在 $minLength–$maxLength 之间');
    }

    final sets = <String>[];
    if (useLowercase) sets.add(_lowercase);
    if (useUppercase) sets.add(_uppercase);
    if (useDigits) sets.add(_digits);
    if (useSymbols) sets.add(_symbols);
    if (sets.isEmpty) {
      throw ArgumentError('至少启用一个字符集');
    }

    String filter(String s) =>
        excludeAmbiguous ? s.split('').where((c) => !ambiguousChars.contains(c)).join() : s;

    final filteredSets = sets.map(filter).where((s) => s.isNotEmpty).toList();
    if (filteredSets.isEmpty) {
      throw ArgumentError('字符集在排除易混淆字符后为空');
    }

    if (length < filteredSets.length) {
      throw ArgumentError('长度不足以覆盖所有启用的字符集');
    }

    final allChars = filteredSets.join();
    final chars = <String>[];

    // 每集至少一个字符
    for (final set in filteredSets) {
      chars.add(set[_random.nextInt(set.length)]);
    }
    // 填满剩余
    while (chars.length < length) {
      chars.add(allChars[_random.nextInt(allChars.length)]);
    }

    // Fisher-Yates 洗牌
    for (var i = chars.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final tmp = chars[i];
      chars[i] = chars[j];
      chars[j] = tmp;
    }

    return chars.join();
  }

  /// 生成 passphrase
  String generatePassphrase({
    int wordCount = 5,
    String separator = '-',
    bool appendDigit = false,
  }) {
    if (wordCount < 2 || wordCount > 12) {
      throw ArgumentError('词数须在 2–12 之间');
    }
    final words = List<String>.generate(
      wordCount,
      (_) => passphraseWordList[_random.nextInt(passphraseWordList.length)],
    );
    var result = words.join(separator);
    if (appendDigit) {
      result += separator + _random.nextInt(10).toString();
    }
    return result;
  }
}

/// 内置 passphrase 词表（~200 高频英文词，子集；设计 D8 暂定英文高频词）
const List<String> passphraseWordList = [
  'apple', 'arrow', 'baker', 'beach', 'berry', 'bird', 'blaze', 'bloom',
  'brave', 'brook', 'cabin', 'candle', 'cedar', 'charm', 'cliff', 'cloud',
  'clover', 'coral', 'crane', 'creek', 'crown', 'dance', 'delta', 'dream',
  'drift', 'eagle', 'ember', 'fable', 'falcon', 'feather', 'field', 'flame',
  'flint', 'forest', 'frost', 'garden', 'gate', 'glacier', 'glen', 'gold',
  'grace', 'granite', 'grove', 'harbor', 'hawk', 'hazel', 'hearth', 'heron',
  'hill', 'holly', 'honey', 'horizon', 'island', 'ivory', 'jade', 'jasmine',
  'jewel', 'juniper', 'kayak', 'keystone', 'kite', 'lagoon', 'lantern',
  'lark', 'laurel', 'lemon', 'lily', 'linen', 'lotus', 'lunar', 'maple',
  'marble', 'meadow', 'mercury', 'mesa', 'mist', 'moon', 'moss', 'north',
  'oak', 'ocean', 'olive', 'onyx', 'opal', 'orchid', 'otter', 'palm',
  'pearl', 'pebble', 'pepper', 'pine', 'plume', 'prairie', 'quartz',
  'quill', 'rain', 'raven', 'reed', 'ridge', 'river', 'robin', 'rose',
  'sage', 'sand', 'sapphire', 'savanna', 'shadow', 'shell', 'shore',
  'sierra', 'silk', 'silver', 'sky', 'slate', 'solar', 'sparrow', 'spring',
  'spruce', 'star', 'stone', 'storm', 'summit', 'sunset', 'swan', 'swift',
  'temple', 'terra', 'thorn', 'tide', 'timber', 'topaz', 'trail', 'tulip',
  'valley', 'velvet', 'violet', 'viper', 'vista', 'walnut', 'wave',
  'willow', 'winter', 'wren', 'zephyr', 'acorn', 'amber', 'anchor',
  'aspen', 'aurora', 'autumn', 'badger', 'basil', 'bayou', 'birch',
  'breeze', 'brook', 'canyon', 'castle', 'cinder', 'citrus', 'clay',
  'comet', 'copper', 'cove', 'crystal', 'cypress', 'dagger', 'dawn',
  'dune', 'dust', 'echo', 'elm', 'falcon', 'fern', 'fjord', 'fox',
  'gale', 'gem', 'glen', 'gulf', 'haven', 'ink', 'iris', 'jet',
  'kelp', 'lake', 'ledge', 'lilac', 'lodestar', 'magnet', 'mars',
  'mint', 'myth', 'nova', 'oasis', 'orbit', 'panda', 'peak', 'plaza',
  'quest', 'reef', 'ridge', 'saber', 'scout', 'shard', 'slope',
  'spark', 'spire', 'stag', 'summit', 'talon', 'torch', 'vale',
  'vapor', 'vertex', 'wolf', 'zenith', 'zinc',
];
