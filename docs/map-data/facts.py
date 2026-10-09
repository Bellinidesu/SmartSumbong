"""
Facts found for buildings of the Newport - NAIA zone, with where each was found. A building whose name matches gets this many floors (3.4 m a floor
and 1.2 m of roof) instead of a size-based guess. Added to as better sources are found; a survey or a permit beats everything here.
"""
FLOORS = [
    # (a pattern in the building's name, floors, where it was found)
    (r'Marriott Grand Ballroom', None, 'OpenStreetMap: height 36 m'),
    (r'Marriot(t)? West Wing', 10, 'Overture Maps: 10 floors'),
    (r'Manila Marriott', 8, 'hotel booking listings (Marriott, Traveloka): 8 floors'),
    (r'Hilton', 10, 'Travel Weekly / AMI Magazine list 9, a hotel listing 11: 10 taken'),
    (r'Sheraton Manila', 11, 'Marriott.com property facilities; booking listings: 11 floors'),
    (r'Okura', 11, 'Hotel Okura Manila: 11 floors and 4 basement levels'),
    (r'Belmont', 10, 'Overture Maps: 10 floors'),
    (r'Holiday Inn', 10, 'Overture Maps: 10 floors'),
    (r'Horizon Centre', 14, 'Overture Maps: 14 floors'),
    (r'Plaza 66', 12, 'Overture Maps: 12 floors'),
    (r'Newport Performing Arts', 5, 'Overture Maps: 5 floors'),
    (r'Multilevel Parking', 5, 'Overture Maps: 5 floors'),
    (r'Steel Carpark', 3, 'Overture Maps: 3 floors'),
    (r'101 Newport|150 Newport|81 Newport', 10, 'Megaworld listings: 10 storeys'),
]
