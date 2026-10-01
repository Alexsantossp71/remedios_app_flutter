class Doctor {
  const Doctor({
    required this.id,
    required this.name,
    this.specialty = '',
    this.crm = '',
    this.crmState = '',
    this.phone = '',
    this.email = '',
    this.clinic = '',
    this.street = '',
    this.number = '',
    this.complement = '',
    this.neighborhood = '',
    this.city = '',
    this.state = '',
    this.postalCode = '',
    this.healthPlans = '',
    this.notes = '',
  });

  final String id;
  final String name;
  final String specialty;
  final String crm;
  final String crmState;
  final String phone;
  final String email;
  final String clinic;
  final String street;
  final String number;
  final String complement;
  final String neighborhood;
  final String city;
  final String state;
  final String postalCode;
  final String healthPlans;
  final String notes;

  String get fullAddress => [
        if (street.isNotEmpty) street,
        if (number.isNotEmpty) number,
        if (complement.isNotEmpty) complement,
        if (neighborhood.isNotEmpty) neighborhood,
        if (city.isNotEmpty) city,
        if (state.isNotEmpty) state,
        if (postalCode.isNotEmpty) postalCode,
      ].join(', ');

  String get crmLabel => [
        if (crm.isNotEmpty) 'CRM $crm',
        if (crmState.isNotEmpty) crmState.toUpperCase(),
      ].join('/');

  factory Doctor.fromJson(Map<String, dynamic> json) {
    return Doctor(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      specialty: json['specialty'] as String? ?? '',
      crm: json['crm'] as String? ?? '',
      crmState: json['crmState'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      clinic: json['clinic'] as String? ?? '',
      street: json['street'] as String? ?? '',
      number: json['number'] as String? ?? '',
      complement: json['complement'] as String? ?? '',
      neighborhood: json['neighborhood'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      postalCode: json['postalCode'] as String? ?? '',
      healthPlans: json['healthPlans'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
    );
  }

  Doctor copyWith({
    String? name,
    String? specialty,
    String? crm,
    String? crmState,
    String? phone,
    String? email,
    String? clinic,
    String? street,
    String? number,
    String? complement,
    String? neighborhood,
    String? city,
    String? state,
    String? postalCode,
    String? healthPlans,
    String? notes,
  }) {
    return Doctor(
      id: id,
      name: name ?? this.name,
      specialty: specialty ?? this.specialty,
      crm: crm ?? this.crm,
      crmState: crmState ?? this.crmState,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      clinic: clinic ?? this.clinic,
      street: street ?? this.street,
      number: number ?? this.number,
      complement: complement ?? this.complement,
      neighborhood: neighborhood ?? this.neighborhood,
      city: city ?? this.city,
      state: state ?? this.state,
      postalCode: postalCode ?? this.postalCode,
      healthPlans: healthPlans ?? this.healthPlans,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'specialty': specialty,
        'crm': crm,
        'crmState': crmState,
        'phone': phone,
        'email': email,
        'clinic': clinic,
        'street': street,
        'number': number,
        'complement': complement,
        'neighborhood': neighborhood,
        'city': city,
        'state': state,
        'postalCode': postalCode,
        'healthPlans': healthPlans,
        'notes': notes,
      };
}
