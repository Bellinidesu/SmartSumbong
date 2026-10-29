// SmartSumbong — the complaint category catalogue.
//
// Figma node 2212:145.
//
// WHAT IS STORED. Since 0146 (Ready for Barangay 183, 29 Oct 2026) the
// categories and the options residents pick under each one ("Potholes",
// "Illegal Parking") are two tables a super admin edits in the portal,
// Settings > Complaint types: names in English and Tagalog, colour, map
// symbol, order, on or off. The app reads them through
// complaint_catalogue() (complaint_catalogue.dart). The list below is what
// the barangay started with, and what the app falls back on before the
// catalogue has ever been read (a first open with no signal).
//
// The option picked is still written into reports.subject, in English, so
// the portal's issue filter matches it whatever language the resident
// reads the app in.
//
// NOTE ON "OTHERS". It has its own value since 0076 (Rose, 2 Oct 2026);
// before that it was filed under peace_order_nuisance. It has no options
// of its own, so the picker shows it as its own card.

import 'complaint_catalogue.dart';

/// One option residents pick under a category.
class ComplaintOption {
  const ComplaintOption(this.en, [String? fil]) : fil = fil ?? en;

  /// The name stored in reports.subject.
  final String en;
  final String fil;
}

/// A value of `public.complaint_category`, with what the barangay set for it.
class ComplaintCategory {
  const ComplaintCategory(this.wire, this.label, this.labelFil, this.colour, this.icon, this.options);

  static const streetObstruction = ComplaintCategory('street_obstruction', 'Street Obstruction', 'Sagabal sa Kalsada', 0xFFF93535,
      'street_obstruction', [ComplaintOption('Obstructed Sidewalks'), ComplaintOption('Illegal Parking'), ComplaintOption('Vendor Blocking Sidewalks')]);
  static const publicSafetyInfrastructure = ComplaintCategory(
      'public_safety_infrastructure', 'Public Safety and Infrastructure', 'Kaligtasan at Imprastraktura', 0xFF356CF9, 'public_safety_infrastructure', [
    ComplaintOption('Dangling Electric Wires'),
    ComplaintOption('Poor Street Lighting'),
    ComplaintOption('Unsecured Construction Site'),
    ComplaintOption('Potholes'),
    ComplaintOption('Open Manholes / Damaged Drainage Covers'),
  ]);
  static const environmentalWasteHazard = ComplaintCategory(
      'environmental_waste_hazard', 'Environmental and Waste Hazards', 'Kapaligiran at Basura', 0xFFF9AB35, 'environmental_waste_hazard', [
    ComplaintOption('Illegal Dumping of Garbage'),
    ComplaintOption('Public Urination'),
    ComplaintOption('Clogged Drainage'),
    ComplaintOption('Foul-Smelling Surrounding'),
    ComplaintOption('Industrial / Commercial Smoke Emission'),
    ComplaintOption('Flooded Street / Road'),
    ComplaintOption('Open Burning of Waste'),
    ComplaintOption('Smoking / Vaping in Prohibited Areas'),
  ]);
  static const animalWelfare = ComplaintCategory('animal_welfare', 'Animal Welfare', 'Kapakanan ng Hayop', 0xFF34C759, 'animal_welfare', [
    ComplaintOption('Animal Cruelty'),
    ComplaintOption('Stray / Nuisance Animals'),
    ComplaintOption('Animal Defecation'),
    ComplaintOption('Neglected Pets'),
  ]);
  static const trafficViolation = ComplaintCategory('traffic_violation', 'Traffic Violation', 'Paglabag sa Trapiko', 0xFF8E9ABB, 'traffic_violation', [
    ComplaintOption('Unregistered / Unlicensed'),
    ComplaintOption('Habal-Habal'),
    ComplaintOption('Excessive Fare'),
    ComplaintOption('Reckless Driving'),
    ComplaintOption('Overloading'),
    ComplaintOption('Abandoning Vehicle'),
  ]);
  static const barangayService = ComplaintCategory('barangay_service', 'Barangay Service', 'Serbisyo ng Barangay', 0xFF422F8A, 'barangay_service', [
    ComplaintOption('Delayed Barangay Response'),
    ComplaintOption('Duty & Negligence'),
    ComplaintOption('Rude Barangay Personnel'),
    ComplaintOption('Document Processing'),
  ]);
  static const peaceOrderNuisance =
      ComplaintCategory('peace_order_nuisance', 'Peace, Order, & Nuisance', 'Kapayapaan, Kaayusan at Istorbo', 0xFFE0609A, 'peace_order_nuisance', [
    ComplaintOption('Troublemaking Loiterer'),
    ComplaintOption('Street Drinking Nuisance'),
    ComplaintOption('Altercations / Street Brawls'),
    ComplaintOption('Unreasonable Neighborhood Noise'),
  ]);
  static const other = ComplaintCategory('other', 'Others', 'Iba pa', 0xFF0F9D9A, 'other', []);

  /// The list the barangay started with, in its order.
  static const builtIn = [
    streetObstruction, publicSafetyInfrastructure, environmentalWasteHazard, animalWelfare,
    trafficViolation, barangayService, peaceOrderNuisance, other,
  ];

  /// What residents can pick today, in the barangay's order.
  static List<ComplaintCategory> get values => ComplaintCatalogue.current;

  /// Reads a stored row's category back out. A category switched off since
  /// keeps its name; one this phone has never heard of gets a readable name
  /// from its key and the Others look until the catalogue is next read.
  static ComplaintCategory parse(String? wire) {
    if (wire == null || wire.isEmpty) return other;
    final known = ComplaintCatalogue.find(wire);
    if (known != null) return known;
    for (final c in builtIn) {
      if (c.wire == wire) return c;
    }
    final name = wire.split('_').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
    return ComplaintCategory(wire, name, name, other.colour, 'other', const []);
  }

  /// The value sent to Postgres. Must match the enum label exactly.
  final String wire;

  /// The card heading, in English and in Tagalog.
  final String label;
  final String labelFil;

  /// 0xAARRGGBB, as the portal shows it.
  final int colour;

  /// Which of the built-in symbols it wears on the map (one of their keys).
  final String icon;

  /// The options under it, in order.
  final List<ComplaintOption> options;

  /// The options' English names (what reports.subject holds).
  List<String> get issues => [for (final o in options) o.en];

  @override
  bool operator ==(Object other) => other is ComplaintCategory && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;
}

/// What the picker hands to the details screen.
class CategoryChoice {
  const CategoryChoice({required this.category, this.issue, this.issueFil});

  final ComplaintCategory category;

  /// The specific option tapped, when one was, in English (stored) and in
  /// Tagalog (shown). Null for "Others".
  final String? issue;
  final String? issueFil;

  /// Heading on the details screen: the option if there is one, since
  /// that is what the resident actually chose.
  String get title => issue ?? category.label;

  /// Seeds reports.subject, which is not null and has no field in the
  /// design. The admin case list shows one row per complaint and needs a
  /// short label; "Potholes" reads better there than the first forty
  /// characters of a description.
  String get subject => issue ?? category.label;

  /// Opens the description so the specific issue survives even though it
  /// is not a column. The resident types after the dash.
  String get descriptionPrefill => issue == null ? '' : '$issue — ';
}
