class LanguageModel {
  final String code;
  final String name;
  final String nativeName;
  final String flag;

  const LanguageModel({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.flag,
  });

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'nativeName': nativeName,
      'flag': flag,
    };
  }

  factory LanguageModel.fromJson(Map<String, dynamic> json) {
    return LanguageModel(
      code: json['code'] as String,
      name: json['name'] as String,
      nativeName: json['nativeName'] as String,
      flag: json['flag'] as String,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LanguageModel && other.code == code;
  }

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() {
    return 'LanguageModel(code: $code, name: $name, nativeName: $nativeName, flag: $flag)';
  }
}