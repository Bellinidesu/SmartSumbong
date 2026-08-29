// SmartSumbong — the complaint category catalogue.
//
// Figma node 2212:145.
//
// WHAT IS STORED AND WHAT IS NOT.
//
// public.complaint_category has seven values and Rose's design has
// exactly those seven groups, so the grouping is the schema. The 38
// specific issues inside them — Potholes, Illegal Parking, Clogged
// Drainage — are hers, not the panel's: the Submit Complaint Report use
// case says the resident "selects the appropriate category menu (e.g.,
// Public Safety, Animal Welfare)", and both its examples are groups.
//
// Adding a subcategory column would put the schema beyond what the panel
// approved, three weeks from defence, for a field the manuscript does
// not describe. So the subtype is prefilled into the description
// instead: the admin reads "Potholes — the one outside 76 Lavender St
// has been there since June" and gets the same information, free-text
// search covers the analytics case, and nothing in Chapter III changes.
//
// A subcategory column belongs in Chapter 5 as future work. If the
// barangay later wants a pie chart of pothole complaints specifically,
// the labels are already here to migrate from.
//
// NOTE ON "OTHERS". The design offers it; the enum has no matching
// value. It maps to peace_order_nuisance with an empty prefill, since
// that is the closest thing to a general bucket and an admin can
// recategorise. Worth raising with Rose and the adviser rather than
// leaving as a silent choice.

import 'package:smartsumbong_core/smartsumbong_core.dart';

/// Mirrors `public.complaint_category` in 0001.
enum ComplaintCategory {
  streetObstruction(
    'street_obstruction',
    'Street Obstruction',
    ['Obstructed Sidewalks', 'Illegal Parking', 'Vendor Blocking Sidewalks'],
  ),
  publicSafetyInfrastructure(
    'public_safety_infrastructure',
    'Public Safety and Infrastructure',
    [
      'Dangling Electric Wires',
      'Poor Street Lighting',
      'Unsecured Construction Site',
      'Potholes',
      'Open Manholes / Damaged Drainage Covers',
    ],
  ),
  environmentalWasteHazard(
    'environmental_waste_hazard',
    'Environmental and Waste Hazards',
    [
      'Illegal Dumping of Garbage',
      'Public Urination',
      'Clogged Drainage',
      'Foul-Smelling Surrounding',
      'Industrial / Commercial Smoke Emission',
      'Flooded Street / Road',
      'Open Burning of Waste',
      'Smoking / Vaping in Prohibited Areas',
    ],
  ),
  animalWelfare(
    'animal_welfare',
    'Animal Welfare',
    [
      'Animal Cruelty',
      'Stray / Nuisance Animals',
      'Animal Defecation',
      'Neglected Pets',
    ],
  ),
  trafficViolation(
    'traffic_violation',
    'Traffic Violation',
    [
      'Unregistered / Unlicensed',
      'Habal-Habal',
      'Excessive Fare',
      'Reckless Driving',
      'Overloading',
      'Abandoning Vehicle',
    ],
  ),
  barangayService(
    'barangay_service',
    'Barangay Service',
    [
      'Delayed Barangay Response',
      'Duty & Negligence',
      'Rude Barangay Personnel',
      'Document Processing',
    ],
  ),
  peaceOrderNuisance(
    'peace_order_nuisance',
    'Peace, Order, & Nuisance',
    [
      'Troublemaking Loiterer',
      'Street Drinking Nuisance',
      'Altercations / Street Brawls',
      'Unreasonable Neighborhood Noise',
    ],
  );

  const ComplaintCategory(this.wire, this.label, this.issues);

  /// Reads a stored row's category back out. Falls back to
  /// peaceOrderNuisance on an unmatched value, for the same reason the
  /// picker maps "Others" there — see this file's own header.
  static ComplaintCategory parse(String? wire) => ComplaintCategory.values
      .firstWhere((c) => c.wire == wire, orElse: () => peaceOrderNuisance);

  /// The value sent to Postgres. Must match the enum label exactly.
  final String wire;

  /// The card heading.
  final String label;

  /// Rose's specific issues. Guidance for the resident and a description
  /// prefill — not stored as a field of their own.
  final List<String> issues;
}

/// What the picker hands to the details screen.
class CategoryChoice {
  const CategoryChoice({required this.category, this.issue});

  final ComplaintCategory category;

  /// The specific issue tapped, when one was. Null for "Others".
  final String? issue;

  /// Heading on the details screen: the issue if there is one, since
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
