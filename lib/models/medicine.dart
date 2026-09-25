class Medicine {
  final String name;
  final String dosage;
  final String presentation;

  const Medicine({
    required this.name,
    required this.dosage,
    required this.presentation,
  });

  factory Medicine.fromJson(Map<String, dynamic> json) {
    return Medicine(
      name: json['name'] as String,
      dosage: json['dosage'] as String,
      presentation: json['presentation'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'dosage': dosage,
      'presentation': presentation,
    };
  }
}