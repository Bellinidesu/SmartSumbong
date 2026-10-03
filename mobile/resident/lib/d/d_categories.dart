// SmartSumbong — category colours (branch D), as the portal and the app
// preview use them: the header of a report or dispatch, map pins.

import 'package:flutter/material.dart';

import '../models/complaint_category.dart';

Color categoryColour(ComplaintCategory c) => switch (c) {
      ComplaintCategory.streetObstruction => const Color(0xFFF93535),
      ComplaintCategory.publicSafetyInfrastructure => const Color(0xFF356CF9),
      ComplaintCategory.environmentalWasteHazard => const Color(0xFFF9AB35),
      ComplaintCategory.animalWelfare => const Color(0xFF34C759),
      ComplaintCategory.trafficViolation => const Color(0xFF8E9ABB),
      ComplaintCategory.barangayService => const Color(0xFF422F8A),
      ComplaintCategory.peaceOrderNuisance => const Color(0xFFE0609A),
      ComplaintCategory.other => const Color(0xFF0F9D9A),
    };
