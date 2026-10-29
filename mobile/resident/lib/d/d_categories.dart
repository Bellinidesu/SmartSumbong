// SmartSumbong — category colours (branch D), as the portal and the app
// preview use them: the header of a report or dispatch, map pins. Since
// 0146 the colour is the barangay's (Settings > Complaint types), and a
// category made there wears the symbol it was given.

import 'package:flutter/material.dart';

import '../models/complaint_category.dart';

Color categoryColour(ComplaintCategory c) => Color(c.colour);

/// The glyph a category wears on its map badge.
IconData categoryGlyph(ComplaintCategory c) => switch (c.icon) {
      'street_obstruction' => Icons.local_parking_rounded,
      'public_safety_infrastructure' => Icons.construction_rounded,
      'environmental_waste_hazard' => Icons.water_drop_rounded,
      'animal_welfare' => Icons.pets_rounded,
      'traffic_violation' => Icons.traffic_rounded,
      'barangay_service' => Icons.account_balance_rounded,
      'peace_order_nuisance' => Icons.volume_up_rounded,
      _ => Icons.more_horiz_rounded,
    };
