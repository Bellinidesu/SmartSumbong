<?php
/**
 * The specific issues under each complaint category, as the resident app's picker lists them
 * (mobile/resident/lib/models/complaint_category.dart). A report's subject holds the issue the resident
 * picked, so Case Reports filters on it (panel ask 3a, 7 Sep 2026). Keep in step with the app's list.
 */
declare(strict_types=1);

const CATEGORY_ISSUES = [
    'street_obstruction' => ['Obstructed Sidewalks', 'Illegal Parking', 'Vendor Blocking Sidewalks'],
    'public_safety_infrastructure' => ['Dangling Electric Wires', 'Poor Street Lighting', 'Unsecured Construction Site', 'Potholes', 'Open Manholes / Damaged Drainage Covers'],
    'environmental_waste_hazard' => ['Illegal Dumping of Garbage', 'Public Urination', 'Clogged Drainage', 'Foul-Smelling Surrounding', 'Industrial / Commercial Smoke Emission', 'Flooded Street / Road', 'Open Burning of Waste', 'Smoking / Vaping in Prohibited Areas'],
    'animal_welfare' => ['Animal Cruelty', 'Stray / Nuisance Animals', 'Animal Defecation', 'Neglected Pets'],
    'traffic_violation' => ['Unregistered / Unlicensed', 'Habal-Habal', 'Excessive Fare', 'Reckless Driving', 'Overloading', 'Abandoning Vehicle'],
    'barangay_service' => ['Delayed Barangay Response', 'Duty & Negligence', 'Rude Barangay Personnel', 'Document Processing'],
    'peace_order_nuisance' => ['Troublemaking Loiterer', 'Street Drinking Nuisance', 'Altercations / Street Brawls', 'Unreasonable Neighborhood Noise'],
];
