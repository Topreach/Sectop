import 'dart:math' as math;

/// Service providing Nigerian states, LGAs, towns and their lat/lng coordinates.
///
/// Users can search by location name (state, LGA, town) and get coordinates.
/// This eliminates the need for users to know latitude/longitude values.
class NigeriaLocationService {
  static final NigeriaLocationService _instance = NigeriaLocationService._();
  factory NigeriaLocationService() => _instance;
  NigeriaLocationService._();

  /// All 36 states + FCT with their capital coordinates.
  static const List<Map<String, dynamic>> states = [
    {'name': 'Abia', 'capital': 'Umuahia', 'latitude': 5.5249, 'longitude': 7.5272},
    {'name': 'Adamawa', 'capital': 'Yola', 'latitude': 9.2035, 'longitude': 12.4954},
    {'name': 'Akwa Ibom', 'capital': 'Uyo', 'latitude': 5.0333, 'longitude': 7.9333},
    {'name': 'Anambra', 'capital': 'Awka', 'latitude': 6.2104, 'longitude': 7.0723},
    {'name': 'Bauchi', 'capital': 'Bauchi', 'latitude': 10.3158, 'longitude': 9.8442},
    {'name': 'Bayelsa', 'capital': 'Yenagoa', 'latitude': 4.9267, 'longitude': 6.2676},
    {'name': 'Benue', 'capital': 'Makurdi', 'latitude': 7.7325, 'longitude': 8.5391},
    {'name': 'Borno', 'capital': 'Maiduguri', 'latitude': 11.8333, 'longitude': 13.1500},
    {'name': 'Cross River', 'capital': 'Calabar', 'latitude': 4.9750, 'longitude': 8.3417},
    {'name': 'Delta', 'capital': 'Asaba', 'latitude': 6.2000, 'longitude': 6.7333},
    {'name': 'Ebonyi', 'capital': 'Abakaliki', 'latitude': 6.3333, 'longitude': 8.1000},
    {'name': 'Edo', 'capital': 'Benin City', 'latitude': 6.3176, 'longitude': 5.6145},
    {'name': 'Ekiti', 'capital': 'Ado Ekiti', 'latitude': 7.6211, 'longitude': 5.2214},
    {'name': 'Enugu', 'capital': 'Enugu', 'latitude': 6.4403, 'longitude': 7.4942},
    {'name': 'FCT', 'capital': 'Abuja', 'latitude': 9.0765, 'longitude': 7.3986},
    {'name': 'Gombe', 'capital': 'Gombe', 'latitude': 10.2897, 'longitude': 11.1667},
    {'name': 'Imo', 'capital': 'Owerri', 'latitude': 5.4833, 'longitude': 7.0333},
    {'name': 'Jigawa', 'capital': 'Dutse', 'latitude': 11.7000, 'longitude': 9.3333},
    {'name': 'Kaduna', 'capital': 'Kaduna', 'latitude': 10.5105, 'longitude': 7.4165},
    {'name': 'Kano', 'capital': 'Kano', 'latitude': 12.0000, 'longitude': 8.5167},
    {'name': 'Katsina', 'capital': 'Katsina', 'latitude': 12.9900, 'longitude': 7.6000},
    {'name': 'Kebbi', 'capital': 'Birnin Kebbi', 'latitude': 12.4500, 'longitude': 4.2000},
    {'name': 'Kogi', 'capital': 'Lokoja', 'latitude': 7.8000, 'longitude': 6.7333},
    {'name': 'Kwara', 'capital': 'Ilorin', 'latitude': 8.5000, 'longitude': 4.5500},
    {'name': 'Lagos', 'capital': 'Ikeja', 'latitude': 6.5244, 'longitude': 3.3792},
    {'name': 'Nasarawa', 'capital': 'Lafia', 'latitude': 8.4833, 'longitude': 8.5167},
    {'name': 'Niger', 'capital': 'Minna', 'latitude': 9.6139, 'longitude': 6.5569},
    {'name': 'Ogun', 'capital': 'Abeokuta', 'latitude': 7.1500, 'longitude': 3.3500},
    {'name': 'Ondo', 'capital': 'Akure', 'latitude': 7.2500, 'longitude': 5.2000},
    {'name': 'Osun', 'capital': 'Osogbo', 'latitude': 7.7667, 'longitude': 4.5667},
    {'name': 'Oyo', 'capital': 'Ibadan', 'latitude': 7.3964, 'longitude': 3.9167},
    {'name': 'Plateau', 'capital': 'Jos', 'latitude': 9.8965, 'longitude': 8.8583},
    {'name': 'Rivers', 'capital': 'Port Harcourt', 'latitude': 4.7500, 'longitude': 7.0000},
    {'name': 'Sokoto', 'capital': 'Sokoto', 'latitude': 13.0667, 'longitude': 5.2500},
    {'name': 'Taraba', 'capital': 'Jalingo', 'latitude': 8.8833, 'longitude': 11.3667},
    {'name': 'Yobe', 'capital': 'Damaturu', 'latitude': 11.7500, 'longitude': 11.9667},
    {'name': 'Zamfara', 'capital': 'Gusau', 'latitude': 12.1667, 'longitude': 6.6667},
  ];

  /// Get state names as a list of strings.
  static List<String> get stateNames =>
      states.map((s) => s['name'] as String).toList();

  /// Get state display names (with FCT formatted).
  static List<String> get stateDisplayNames =>
      states.map((s) => s['name'] == 'FCT' ? 'Abuja (FCT)' : s['name'] as String).toList();

  /// Get coordinates for a state capital.
  static Map<String, dynamic>? getStateCapital(String stateName) {
    try {
      final state = states.firstWhere(
        (s) => s['name'].toString().toLowerCase() == stateName.toLowerCase(),
      );
      return {
        'name': state['capital'],
        'latitude': state['latitude'],
        'longitude': state['longitude'],
        'state': state['name'],
      };
    } catch (_) {
      return null;
    }
  }

  /// Search for any location by name (state, town, or capital).
  /// Returns a list of matching results with coordinates.
  static List<Map<String, dynamic>> searchLocation(String query) {
    if (query.trim().isEmpty) return [];
    final q = query.toLowerCase().trim();
    final results = <Map<String, dynamic>>[];

    // Search states
    for (final state in states) {
      if (state['name'].toString().toLowerCase().contains(q) ||
          state['capital'].toString().toLowerCase().contains(q)) {
        results.add({
          'name': state['capital'],
          'state': state['name'],
          'latitude': state['latitude'],
          'longitude': state['longitude'],
          'type': 'state_capital',
          'displayName': '${state['capital']}, ${state['name']} State',
        });
      }
    }

    // Search towns
    for (final entry in townsByState.entries) {
      final stateName = entry.key;
      for (final town in entry.value) {
        if (town['name'].toString().toLowerCase().contains(q)) {
          results.add({
            'name': town['name'],
            'state': stateName,
            'latitude': town['latitude'],
            'longitude': town['longitude'],
            'type': 'town',
            'displayName': '${town['name']}, $stateName',
          });
        }
      }
    }

    return results;
  }

  /// Get towns for a given state.
  static List<Map<String, dynamic>> getTownsForState(String stateName) {
    // Try exact match first
    if (townsByState.containsKey(stateName)) {
      return townsByState[stateName]!;
    }
    // Try matching "Abuja (FCT)" for "FCT"
    if (stateName == 'FCT') {
      return townsByState['Abuja (FCT)'] ?? [];
    }
    // Try case-insensitive match
    for (final entry in townsByState.entries) {
      if (entry.key.toLowerCase().contains(stateName.toLowerCase())) {
        return entry.value;
      }
    }
    return [];
  }

  /// Get the display name for a state (handles FCT -> Abuja (FCT)).
  static String getStateDisplayName(String stateName) {
    if (stateName == 'FCT') return 'Abuja (FCT)';
    return stateName;
  }

  /// Major towns/cities in each state with their coordinates.
  static const Map<String, List<Map<String, dynamic>>> townsByState = {
    'Abuja (FCT)': [
      {'name': 'Abuja City Centre', 'latitude': 9.0765, 'longitude': 7.3986},
      {'name': 'Garki', 'latitude': 9.0192, 'longitude': 7.4889},
      {'name': 'Wuse', 'latitude': 9.0765, 'longitude': 7.4769},
      {'name': 'Maitama', 'latitude': 9.0833, 'longitude': 7.5000},
      {'name': 'Gwarinpa', 'latitude': 9.0000, 'longitude': 7.4167},
      {'name': 'Kubwa', 'latitude': 9.1500, 'longitude': 7.3333},
      {'name': 'Bwari', 'latitude': 9.2833, 'longitude': 7.3833},
      {'name': 'Karu', 'latitude': 8.9833, 'longitude': 7.6167},
      {'name': 'Nyanya', 'latitude': 8.9333, 'longitude': 7.5500},
      {'name': 'Lugbe', 'latitude': 8.9833, 'longitude': 7.3500},
    ],
    'Lagos': [
      {'name': 'Ikeja', 'latitude': 6.6018, 'longitude': 3.3515},
      {'name': 'Lagos Island', 'latitude': 6.4551, 'longitude': 3.3945},
      {'name': 'Victoria Island', 'latitude': 6.4281, 'longitude': 3.4219},
      {'name': 'Lekki', 'latitude': 6.4586, 'longitude': 3.6017},
      {'name': 'Surulere', 'latitude': 6.5000, 'longitude': 3.3500},
      {'name': 'Yaba', 'latitude': 6.5167, 'longitude': 3.3667},
      {'name': 'Mushin', 'latitude': 6.5333, 'longitude': 3.3500},
      {'name': 'Oshodi', 'latitude': 6.5500, 'longitude': 3.3500},
      {'name': 'Agege', 'latitude': 6.6167, 'longitude': 3.3333},
      {'name': 'Badagry', 'latitude': 6.4167, 'longitude': 2.8833},
      {'name': 'Epe', 'latitude': 6.5833, 'longitude': 3.9833},
      {'name': 'Ikorodu', 'latitude': 6.6000, 'longitude': 3.5000},
      {'name': 'Apapa', 'latitude': 6.4500, 'longitude': 3.3667},
      {'name': 'Ajegunle', 'latitude': 6.4667, 'longitude': 3.3333},
      {'name': 'Bariga', 'latitude': 6.5333, 'longitude': 3.3833},
      {'name': 'Ebute Metta', 'latitude': 6.4833, 'longitude': 3.3833},
      {'name': 'Marina', 'latitude': 6.4500, 'longitude': 3.4000},
      {'name': 'Ikoyi', 'latitude': 6.4500, 'longitude': 3.4333},
      {'name': 'Ojo', 'latitude': 6.4667, 'longitude': 3.2000},
      {'name': 'Amuwo Odofin', 'latitude': 6.4500, 'longitude': 3.2667},
    ],
    'Kano': [
      {'name': 'Kano City', 'latitude': 12.0000, 'longitude': 8.5167},
      {'name': 'Nasarawa', 'latitude': 11.9833, 'longitude': 8.5333},
      {'name': 'Fagge', 'latitude': 12.0000, 'longitude': 8.5333},
      {'name': 'Dala', 'latitude': 12.0167, 'longitude': 8.5000},
      {'name': 'Gwale', 'latitude': 11.9833, 'longitude': 8.4833},
      {'name': 'Tarauni', 'latitude': 11.9667, 'longitude': 8.5500},
      {'name': 'Ungogo', 'latitude': 12.0833, 'longitude': 8.5000},
      {'name': 'Kumbotso', 'latitude': 11.8833, 'longitude': 8.5000},
      {'name': 'Wudil', 'latitude': 11.8167, 'longitude': 8.8500},
      {'name': 'Rano', 'latitude': 11.5500, 'longitude': 8.5833},
    ],
    'Borno': [
      {'name': 'Maiduguri', 'latitude': 11.8333, 'longitude': 13.1500},
      {'name': 'Biu', 'latitude': 10.6167, 'longitude': 12.1833},
      {'name': 'Bama', 'latitude': 11.5167, 'longitude': 13.6833},
      {'name': 'Dikwa', 'latitude': 12.0333, 'longitude': 13.9167},
      {'name': 'Monguno', 'latitude': 12.6167, 'longitude': 13.6167},
      {'name': 'Gwoza', 'latitude': 11.0833, 'longitude': 13.7000},
      {'name': 'Konduga', 'latitude': 11.6500, 'longitude': 13.4167},
      {'name': 'Mafa', 'latitude': 11.9167, 'longitude': 13.6000},
      {'name': 'Kaga', 'latitude': 11.6500, 'longitude': 12.9833},
      {'name': 'Jere', 'latitude': 11.7833, 'longitude': 13.2333},
    ],
    'Kaduna': [
      {'name': 'Kaduna City', 'latitude': 10.5105, 'longitude': 7.4165},
      {'name': 'Zaria', 'latitude': 11.0667, 'longitude': 7.7000},
      {'name': 'Kafanchan', 'latitude': 9.5833, 'longitude': 8.3000},
      {'name': 'Kachia', 'latitude': 9.8667, 'longitude': 7.9500},
      {'name': 'Birnin Gwari', 'latitude': 10.6667, 'longitude': 6.5333},
      {'name': 'Giwa', 'latitude': 11.1333, 'longitude': 7.4500},
      {'name': 'Igabi', 'latitude': 10.8167, 'longitude': 7.4333},
      {'name': "Jema'a", 'latitude': 9.4500, 'longitude': 8.3500},
      {'name': 'Sanga', 'latitude': 9.5333, 'longitude': 8.4833},
      {'name': 'Sabon Gari', 'latitude': 11.1167, 'longitude': 7.7333},
    ],
    'Rivers': [
      {'name': 'Port Harcourt', 'latitude': 4.7500, 'longitude': 7.0000},
      {'name': 'Obio-Akpor', 'latitude': 4.8500, 'longitude': 6.9833},
      {'name': 'Bonny', 'latitude': 4.4333, 'longitude': 7.1667},
      {'name': 'Degema', 'latitude': 4.7500, 'longitude': 6.7667},
      {'name': 'Ahoada', 'latitude': 5.0833, 'longitude': 6.6500},
      {'name': 'Omoku', 'latitude': 5.3500, 'longitude': 6.6500},
      {'name': 'Bori', 'latitude': 4.6833, 'longitude': 7.3667},
      {'name': 'Elele', 'latitude': 5.1000, 'longitude': 6.8167},
      {'name': 'Oyigbo', 'latitude': 4.8833, 'longitude': 7.1333},
      {'name': 'Okrika', 'latitude': 4.7333, 'longitude': 7.0833},
    ],
    'Oyo': [
      {'name': 'Ibadan', 'latitude': 7.3964, 'longitude': 3.9167},
      {'name': 'Ogbomoso', 'latitude': 8.1333, 'longitude': 4.2500},
      {'name': 'Oyo Town', 'latitude': 7.8500, 'longitude': 3.9333},
      {'name': 'Iseyin', 'latitude': 7.9667, 'longitude': 3.6000},
      {'name': 'Saki', 'latitude': 8.6667, 'longitude': 3.4000},
      {'name': 'Kishi', 'latitude': 9.0833, 'longitude': 3.8500},
      {'name': 'Igbo Ora', 'latitude': 7.4333, 'longitude': 3.2833},
      {'name': 'Eruwa', 'latitude': 7.5333, 'longitude': 3.4167},
      {'name': 'Okeho', 'latitude': 8.0333, 'longitude': 3.3500},
      {'name': 'Lalupon', 'latitude': 7.4667, 'longitude': 4.0667},
    ],
    'Delta': [
      {'name': 'Asaba', 'latitude': 6.2000, 'longitude': 6.7333},
      {'name': 'Warri', 'latitude': 5.5167, 'longitude': 5.7500},
      {'name': 'Sapele', 'latitude': 5.9000, 'longitude': 5.6667},
      {'name': 'Ughelli', 'latitude': 5.5000, 'longitude': 6.0000},
      {'name': 'Agbor', 'latitude': 6.2500, 'longitude': 6.2000},
      {'name': 'Kwale', 'latitude': 5.7167, 'longitude': 6.4333},
      {'name': 'Ozoro', 'latitude': 5.5500, 'longitude': 6.2333},
      {'name': 'Burutu', 'latitude': 5.3500, 'longitude': 5.5167},
      {'name': 'Bomadi', 'latitude': 5.1667, 'longitude': 5.9167},
      {'name': 'Patani', 'latitude': 5.2333, 'longitude': 6.2000},
    ],
    'Edo': [
      {'name': 'Benin City', 'latitude': 6.3176, 'longitude': 5.6145},
      {'name': 'Auchi', 'latitude': 7.0667, 'longitude': 6.2667},
      {'name': 'Ekpoma', 'latitude': 6.7333, 'longitude': 6.1333},
      {'name': 'Uromi', 'latitude': 6.7000, 'longitude': 6.3333},
      {'name': 'Irrua', 'latitude': 6.7333, 'longitude': 6.2167},
      {'name': 'Igueben', 'latitude': 6.6000, 'longitude': 6.2833},
      {'name': 'Okada', 'latitude': 6.7333, 'longitude': 5.3833},
      {'name': 'Ubiaja', 'latitude': 6.6500, 'longitude': 6.3833},
      {'name': 'Sabongida-Ora', 'latitude': 6.9000, 'longitude': 5.9333},
      {'name': 'Igarra', 'latitude': 7.2833, 'longitude': 6.1000},
    ],
    'Enugu': [
      {'name': 'Enugu City', 'latitude': 6.4403, 'longitude': 7.4942},
      {'name': 'Nsukka', 'latitude': 6.8500, 'longitude': 7.3833},
      {'name': 'Awgu', 'latitude': 6.0667, 'longitude': 7.4667},
      {'name': 'Oji River', 'latitude': 6.2667, 'longitude': 7.2667},
      {'name': 'Udi', 'latitude': 6.3167, 'longitude': 7.4167},
      {'name': 'Enugu Ezike', 'latitude': 6.9833, 'longitude': 7.5500},
      {'name': 'Agbani', 'latitude': 6.3167, 'longitude': 7.5500},
      {'name': 'Nkanu', 'latitude': 6.2667, 'longitude': 7.6000},
      {'name': 'Ezeagu', 'latitude': 6.4167, 'longitude': 7.3833},
      {'name': 'Igbo-Eze', 'latitude': 6.9333, 'longitude': 7.4667},
    ],
    'Anambra': [
      {'name': 'Awka', 'latitude': 6.2104, 'longitude': 7.0723},
      {'name': 'Onitsha', 'latitude': 6.1667, 'longitude': 6.7833},
      {'name': 'Nnewi', 'latitude': 6.0167, 'longitude': 6.9167},
      {'name': 'Ekwulobia', 'latitude': 6.0167, 'longitude': 7.0667},
      {'name': 'Agulu', 'latitude': 6.1000, 'longitude': 7.0000},
      {'name': 'Oba', 'latitude': 6.0833, 'longitude': 6.7833},
      {'name': 'Umunze', 'latitude': 5.9667, 'longitude': 7.0167},
      {'name': 'Ogidi', 'latitude': 6.1500, 'longitude': 6.8667},
      {'name': 'Abagana', 'latitude': 6.1833, 'longitude': 6.9333},
      {'name': 'Nkpor', 'latitude': 6.1500, 'longitude': 6.8333},
    ],
    'Imo': [
      {'name': 'Owerri', 'latitude': 5.4833, 'longitude': 7.0333},
      {'name': 'Orlu', 'latitude': 5.7833, 'longitude': 7.0333},
      {'name': 'Okigwe', 'latitude': 5.8167, 'longitude': 7.3500},
      {'name': 'Mbaise', 'latitude': 5.5833, 'longitude': 7.2667},
      {'name': 'Oguta', 'latitude': 5.7167, 'longitude': 6.7833},
      {'name': 'Mbano', 'latitude': 5.6833, 'longitude': 7.1667},
      {'name': 'Nkwerre', 'latitude': 5.7500, 'longitude': 7.1000},
      {'name': 'Ehime Mbano', 'latitude': 5.6833, 'longitude': 7.1833},
      {'name': 'Ikeduru', 'latitude': 5.5333, 'longitude': 7.0333},
      {'name': 'Obowo', 'latitude': 5.5500, 'longitude': 7.3667},
    ],
    'Akwa Ibom': [
      {'name': 'Uyo', 'latitude': 5.0333, 'longitude': 7.9333},
      {'name': 'Eket', 'latitude': 4.6500, 'longitude': 7.9333},
      {'name': 'Ikot Ekpene', 'latitude': 5.1833, 'longitude': 7.7167},
      {'name': 'Oron', 'latitude': 4.8167, 'longitude': 8.2333},
      {'name': 'Abak', 'latitude': 5.0000, 'longitude': 7.7833},
      {'name': 'Ikono', 'latitude': 5.1333, 'longitude': 7.9000},
      {'name': 'Etinan', 'latitude': 5.0167, 'longitude': 7.8500},
      {'name': 'Ikot Abasi', 'latitude': 4.5667, 'longitude': 7.5667},
      {'name': 'Ukanafun', 'latitude': 4.9833, 'longitude': 7.6833},
      {'name': 'Mkpat Enin', 'latitude': 4.7333, 'longitude': 7.7833},
    ],
    'Abia': [
      {'name': 'Umuahia', 'latitude': 5.5249, 'longitude': 7.5272},
      {'name': 'Aba', 'latitude': 5.1167, 'longitude': 7.3667},
      {'name': 'Ohafia', 'latitude': 5.6167, 'longitude': 7.8333},
      {'name': 'Arochukwu', 'latitude': 5.3833, 'longitude': 7.9167},
      {'name': 'Bende', 'latitude': 5.5667, 'longitude': 7.6333},
      {'name': 'Isuikwuato', 'latitude': 5.8333, 'longitude': 7.4833},
      {'name': 'Ukwa', 'latitude': 5.0167, 'longitude': 7.2667},
      {'name': 'Ikwuano', 'latitude': 5.4333, 'longitude': 7.5667},
      {'name': 'Osisioma', 'latitude': 5.1500, 'longitude': 7.3333},
      {'name': 'Ugwunagbo', 'latitude': 5.1167, 'longitude': 7.2833},
    ],
    'Plateau': [
      {'name': 'Jos', 'latitude': 9.8965, 'longitude': 8.8583},
      {'name': 'Bukuru', 'latitude': 9.8000, 'longitude': 8.8667},
      {'name': 'Pankshin', 'latitude': 9.3333, 'longitude': 9.4500},
      {'name': 'Shendam', 'latitude': 8.8833, 'longitude': 9.5333},
      {'name': 'Barkin Ladi', 'latitude': 9.5333, 'longitude': 8.9000},
      {'name': 'Mangu', 'latitude': 9.5167, 'longitude': 9.1000},
      {'name': 'Langtang', 'latitude': 9.1333, 'longitude': 9.7833},
      {'name': 'Wase', 'latitude': 9.0833, 'longitude': 9.9667},
      {'name': 'Kanke', 'latitude': 9.3833, 'longitude': 9.3333},
      {'name': 'Riyom', 'latitude': 9.6333, 'longitude': 8.7500},
    ],
    'Niger': [
      {'name': 'Minna', 'latitude': 9.6139, 'longitude': 6.5569},
      {'name': 'Bida', 'latitude': 9.0833, 'longitude': 6.0167},
      {'name': 'Kontagora', 'latitude': 10.4000, 'longitude': 5.4667},
      {'name': 'Suleja', 'latitude': 9.1833, 'longitude': 7.1833},
      {'name': 'Lapai', 'latitude': 9.0500, 'longitude': 6.5667},
      {'name': 'Agaie', 'latitude': 9.0167, 'longitude': 6.3167},
      {'name': 'Rijau', 'latitude': 10.8333, 'longitude': 5.2500},
      {'name': 'Mokwa', 'latitude': 9.3000, 'longitude': 5.0500},
      {'name': 'New Bussa', 'latitude': 9.8833, 'longitude': 4.5167},
      {'name': 'Kuta', 'latitude': 9.8667, 'longitude': 6.7167},
    ],
    'Ogun': [
      {'name': 'Abeokuta', 'latitude': 7.1500, 'longitude': 3.3500},
      {'name': 'Ijebu Ode', 'latitude': 6.8167, 'longitude': 3.9167},
      {'name': 'Sagamu', 'latitude': 6.8500, 'longitude': 3.6500},
      {'name': 'Ilaro', 'latitude': 6.8833, 'longitude': 3.0167},
      {'name': 'Owode', 'latitude': 6.9500, 'longitude': 3.5000},
      {'name': 'Ado Odo', 'latitude': 6.6000, 'longitude': 2.9333},
      {'name': 'Ifo', 'latitude': 6.8167, 'longitude': 3.2000},
      {'name': 'Ota', 'latitude': 6.6833, 'longitude': 3.2333},
      {'name': 'Iperu', 'latitude': 6.9167, 'longitude': 3.6500},
      {'name': 'Ayetoro', 'latitude': 6.9000, 'longitude': 2.9333},
    ],
    'Katsina': [
      {'name': 'Katsina City', 'latitude': 12.9900, 'longitude': 7.6000},
      {'name': 'Daura', 'latitude': 13.0333, 'longitude': 8.3167},
      {'name': 'Funtua', 'latitude': 11.5333, 'longitude': 7.3167},
      {'name': 'Malumfashi', 'latitude': 11.7833, 'longitude': 7.6167},
      {'name': 'Kankia', 'latitude': 12.1333, 'longitude': 7.8167},
      {'name': 'Bakori', 'latitude': 11.5833, 'longitude': 7.4333},
      {'name': 'Mani', 'latitude': 12.8500, 'longitude': 7.8833},
      {'name': 'Zango', 'latitude': 13.0500, 'longitude': 8.5333},
      {'name': 'Batagarawa', 'latitude': 12.9000, 'longitude': 7.6000},
      {'name': 'Bindawa', 'latitude': 12.6667, 'longitude': 7.8000},
    ],
    'Bauchi': [
      {'name': 'Bauchi City', 'latitude': 10.3158, 'longitude': 9.8442},
      {'name': 'Azare', 'latitude': 11.6833, 'longitude': 10.2000},
      {'name': 'Misau', 'latitude': 11.3167, 'longitude': 10.4667},
      {'name': "Jama'are", 'latitude': 11.6667, 'longitude': 9.9333},
      {'name': 'Katagum', 'latitude': 11.5333, 'longitude': 10.0833},
      {'name': 'Ningi', 'latitude': 11.0667, 'longitude': 9.5667},
      {'name': 'Darazo', 'latitude': 10.9833, 'longitude': 10.4167},
      {'name': 'Gamawa', 'latitude': 11.5333, 'longitude': 10.2333},
      {'name': 'Giade', 'latitude': 11.3833, 'longitude': 10.2000},
      {'name': 'Shira', 'latitude': 11.5000, 'longitude': 10.0333},
    ],
    'Adamawa': [
      {'name': 'Yola', 'latitude': 9.2035, 'longitude': 12.4954},
      {'name': 'Mubi', 'latitude': 10.2667, 'longitude': 13.2667},
      {'name': 'Numan', 'latitude': 9.4667, 'longitude': 12.0333},
      {'name': 'Jimeta', 'latitude': 9.2833, 'longitude': 12.4500},
      {'name': 'Gombi', 'latitude': 10.1667, 'longitude': 12.7333},
      {'name': 'Hong', 'latitude': 10.2333, 'longitude': 12.9333},
      {'name': 'Mayo Belwa', 'latitude': 8.9500, 'longitude': 12.0500},
      {'name': 'Ganye', 'latitude': 8.4333, 'longitude': 12.0500},
      {'name': 'Michika', 'latitude': 10.6167, 'longitude': 13.3833},
      {'name': 'Shelleng', 'latitude': 9.8833, 'longitude': 12.0000},
    ],
    'Sokoto': [
      {'name': 'Sokoto City', 'latitude': 13.0667, 'longitude': 5.2500},
      {'name': 'Gwadabawa', 'latitude': 13.3667, 'longitude': 5.2333},
      {'name': 'Wurno', 'latitude': 13.2833, 'longitude': 5.4167},
      {'name': 'Rabah', 'latitude': 13.1167, 'longitude': 5.5000},
      {'name': 'Tambuwal', 'latitude': 12.4000, 'longitude': 4.6500},
      {'name': 'Yabo', 'latitude': 12.7167, 'longitude': 4.9833},
      {'name': 'Bodinga', 'latitude': 13.0000, 'longitude': 5.1500},
      {'name': 'Dange', 'latitude': 12.8500, 'longitude': 5.3500},
      {'name': 'Illela', 'latitude': 13.7333, 'longitude': 5.3000},
      {'name': 'Binji', 'latitude': 13.2167, 'longitude': 4.9500},
    ],
    'Kebbi': [
      {'name': 'Birnin Kebbi', 'latitude': 12.4500, 'longitude': 4.2000},
      {'name': 'Argungu', 'latitude': 12.7333, 'longitude': 4.5333},
      {'name': 'Yauri', 'latitude': 10.7000, 'longitude': 4.7500},
      {'name': 'Zuru', 'latitude': 11.4333, 'longitude': 5.2333},
      {'name': 'Jega', 'latitude': 12.2167, 'longitude': 4.3833},
      {'name': 'Kamba', 'latitude': 11.8500, 'longitude': 3.6500},
      {'name': 'Dakingari', 'latitude': 11.6500, 'longitude': 4.0667},
      {'name': 'Koko', 'latitude': 11.4167, 'longitude': 4.5167},
      {'name': 'Bagudo', 'latitude': 11.4000, 'longitude': 4.2333},
      {'name': 'Kalgo', 'latitude': 12.3167, 'longitude': 4.2000},
    ],
    'Zamfara': [
      {'name': 'Gusau', 'latitude': 12.1667, 'longitude': 6.6667},
      {'name': 'Kaura Namoda', 'latitude': 12.6000, 'longitude': 6.6000},
      {'name': 'Talata Mafara', 'latitude': 12.5667, 'longitude': 6.0667},
      {'name': 'Anka', 'latitude': 12.1167, 'longitude': 5.9333},
      {'name': 'Bungudu', 'latitude': 12.2667, 'longitude': 6.5500},
      {'name': 'Maradun', 'latitude': 12.5667, 'longitude': 6.2500},
      {'name': 'Shinkafi', 'latitude': 12.5000, 'longitude': 6.5000},
      {'name': 'Bakura', 'latitude': 12.6333, 'longitude': 5.8667},
      {'name': 'Tsafe', 'latitude': 12.0500, 'longitude': 6.0833},
      {'name': 'Gummi', 'latitude': 12.1500, 'longitude': 5.1167},
    ],
    'Benue': [
      {'name': 'Makurdi', 'latitude': 7.7325, 'longitude': 8.5391},
      {'name': 'Gboko', 'latitude': 7.3167, 'longitude': 9.0000},
      {'name': 'Otukpo', 'latitude': 7.2000, 'longitude': 8.1333},
      {'name': 'Katsina-Ala', 'latitude': 7.1667, 'longitude': 9.2833},
      {'name': 'Vandeikya', 'latitude': 6.7833, 'longitude': 9.0667},
      {'name': 'Adikpo', 'latitude': 6.8833, 'longitude': 9.2333},
      {'name': 'Ugbokolo', 'latitude': 7.1000, 'longitude': 8.9833},
      {'name': 'Aliade', 'latitude': 7.2833, 'longitude': 8.4833},
      {'name': 'Lessel', 'latitude': 7.1333, 'longitude': 9.0167},
      {'name': 'Buruku', 'latitude': 7.4500, 'longitude': 9.2000},
    ],
    'Kogi': [
      {'name': 'Lokoja', 'latitude': 7.8000, 'longitude': 6.7333},
      {'name': 'Okene', 'latitude': 7.5500, 'longitude': 6.2333},
      {'name': 'Kabba', 'latitude': 7.9833, 'longitude': 6.0667},
      {'name': 'Idah', 'latitude': 7.0833, 'longitude': 6.7333},
      {'name': 'Ankpa', 'latitude': 7.3667, 'longitude': 7.6333},
      {'name': 'Dekina', 'latitude': 7.2667, 'longitude': 7.0333},
      {'name': 'Ogaminana', 'latitude': 7.5833, 'longitude': 6.2167},
      {'name': 'Koton Karfe', 'latitude': 7.8833, 'longitude': 6.8000},
      {'name': 'Ajaokuta', 'latitude': 7.5667, 'longitude': 6.6500},
      {'name': 'Isanlu', 'latitude': 8.2667, 'longitude': 5.8167},
    ],
    'Kwara': [
      {'name': 'Ilorin', 'latitude': 8.5000, 'longitude': 4.5500},
      {'name': 'Offa', 'latitude': 8.1500, 'longitude': 4.7167},
      {'name': 'Ilorin South', 'latitude': 8.4667, 'longitude': 4.5667},
      {'name': 'Omu Aran', 'latitude': 8.1333, 'longitude': 5.1000},
      {'name': 'Jebba', 'latitude': 9.1167, 'longitude': 4.8167},
      {'name': 'Lafiagi', 'latitude': 8.8667, 'longitude': 5.4167},
      {'name': 'Patigi', 'latitude': 8.7333, 'longitude': 5.7500},
      {'name': 'Kaiama', 'latitude': 9.6167, 'longitude': 3.9333},
      {'name': 'Share', 'latitude': 8.8000, 'longitude': 4.9833},
      {'name': 'Bode Saadu', 'latitude': 8.7000, 'longitude': 4.7833},
    ],
    'Ondo': [
      {'name': 'Akure', 'latitude': 7.2500, 'longitude': 5.2000},
      {'name': 'Ondo City', 'latitude': 7.0833, 'longitude': 4.8333},
      {'name': 'Owo', 'latitude': 7.1833, 'longitude': 5.5833},
      {'name': 'Ikare', 'latitude': 7.5167, 'longitude': 5.7500},
      {'name': 'Okitipupa', 'latitude': 6.5000, 'longitude': 4.7833},
      {'name': 'Ore', 'latitude': 6.7167, 'longitude': 4.8667},
      {'name': 'Idanre', 'latitude': 7.1167, 'longitude': 5.1167},
      {'name': 'Igbokoda', 'latitude': 6.3500, 'longitude': 4.8000},
      {'name': 'Ifon', 'latitude': 6.9167, 'longitude': 5.7667},
      {'name': 'Emure', 'latitude': 7.4333, 'longitude': 5.4500},
    ],
    'Osun': [
      {'name': 'Osogbo', 'latitude': 7.7667, 'longitude': 4.5667},
      {'name': 'Ile-Ife', 'latitude': 7.4833, 'longitude': 4.5500},
      {'name': 'Ilesa', 'latitude': 7.6167, 'longitude': 4.7333},
      {'name': 'Ede', 'latitude': 7.7333, 'longitude': 4.4333},
      {'name': 'Iwo', 'latitude': 7.6333, 'longitude': 4.1833},
      {'name': 'Ikire', 'latitude': 7.3500, 'longitude': 4.1833},
      {'name': 'Ejigbo', 'latitude': 7.9000, 'longitude': 4.3167},
      {'name': 'Ila Orangun', 'latitude': 8.0167, 'longitude': 4.9000},
      {'name': 'Ipetumodu', 'latitude': 7.5167, 'longitude': 4.4500},
      {'name': 'Apomu', 'latitude': 7.3500, 'longitude': 4.1833},
    ],
    'Cross River': [
      {'name': 'Calabar', 'latitude': 4.9750, 'longitude': 8.3417},
      {'name': 'Ugep', 'latitude': 5.8000, 'longitude': 8.0833},
      {'name': 'Ikom', 'latitude': 5.9667, 'longitude': 8.7167},
      {'name': 'Obudu', 'latitude': 6.6667, 'longitude': 9.1667},
      {'name': 'Ogoja', 'latitude': 6.6500, 'longitude': 8.8000},
      {'name': 'Akamkpa', 'latitude': 5.3167, 'longitude': 8.4000},
      {'name': 'Obubra', 'latitude': 6.0833, 'longitude': 8.3333},
      {'name': 'Bekwarra', 'latitude': 6.7000, 'longitude': 8.9833},
      {'name': 'Yala', 'latitude': 6.5500, 'longitude': 8.7667},
      {'name': 'Odukpani', 'latitude': 5.1333, 'longitude': 8.3333},
    ],
    'Bayelsa': [
      {'name': 'Yenagoa', 'latitude': 4.9267, 'longitude': 6.2676},
      {'name': 'Brass', 'latitude': 4.3167, 'longitude': 6.2333},
      {'name': 'Ogbia', 'latitude': 4.6833, 'longitude': 6.3167},
      {'name': 'Sagbama', 'latitude': 5.1500, 'longitude': 6.2000},
      {'name': 'Ekeremor', 'latitude': 5.0333, 'longitude': 5.7833},
      {'name': 'Nembe', 'latitude': 4.5333, 'longitude': 6.4000},
      {'name': 'Amassoma', 'latitude': 4.9667, 'longitude': 6.1000},
      {'name': 'Kaiama', 'latitude': 4.7833, 'longitude': 6.2500},
      {'name': 'Okpoama', 'latitude': 4.3833, 'longitude': 6.1833},
      {'name': 'Twon-Brass', 'latitude': 4.3167, 'longitude': 6.2333},
    ],
    'Ebonyi': [
      {'name': 'Abakaliki', 'latitude': 6.3333, 'longitude': 8.1000},
      {'name': 'Afikpo', 'latitude': 5.8833, 'longitude': 7.9333},
      {'name': 'Onueke', 'latitude': 6.1500, 'longitude': 8.0333},
      {'name': 'Ishieke', 'latitude': 6.3833, 'longitude': 8.1000},
      {'name': 'Ezzamgbo', 'latitude': 6.2500, 'longitude': 7.9833},
      {'name': 'Uburu', 'latitude': 6.0167, 'longitude': 7.7667},
      {'name': 'Okposi', 'latitude': 6.0000, 'longitude': 7.7167},
      {'name': 'Amasiri', 'latitude': 5.9333, 'longitude': 7.8833},
      {'name': 'Edda', 'latitude': 5.8167, 'longitude': 7.8833},
      {'name': 'Ohaozara', 'latitude': 6.0000, 'longitude': 7.7833},
    ],
    'Ekiti': [
      {'name': 'Ado Ekiti', 'latitude': 7.6211, 'longitude': 5.2214},
      {'name': 'Ikere Ekiti', 'latitude': 7.5000, 'longitude': 5.2333},
      {'name': 'Ilawe Ekiti', 'latitude': 7.6000, 'longitude': 5.1000},
      {'name': 'Ijero Ekiti', 'latitude': 7.8167, 'longitude': 5.0667},
      {'name': 'Ifaki Ekiti', 'latitude': 7.7833, 'longitude': 5.2333},
      {'name': 'Oye Ekiti', 'latitude': 7.8000, 'longitude': 5.3333},
      {'name': 'Ise Ekiti', 'latitude': 7.4667, 'longitude': 5.4167},
      {'name': 'Emure Ekiti', 'latitude': 7.4333, 'longitude': 5.4500},
      {'name': 'Aramoko Ekiti', 'latitude': 7.7000, 'longitude': 5.0333},
      {'name': 'Ikole Ekiti', 'latitude': 7.8833, 'longitude': 5.5167},
    ],
    'Gombe': [
      {'name': 'Gombe City', 'latitude': 10.2897, 'longitude': 11.1667},
      {'name': 'Kumo', 'latitude': 10.0500, 'longitude': 11.2167},
      {'name': 'Billiri', 'latitude': 9.8667, 'longitude': 11.2167},
      {'name': 'Dukku', 'latitude': 10.8167, 'longitude': 10.7667},
      {'name': 'Nafada', 'latitude': 11.0833, 'longitude': 11.3333},
      {'name': 'Bajoga', 'latitude': 10.8500, 'longitude': 11.4333},
      {'name': 'Kaltungo', 'latitude': 10.3167, 'longitude': 11.3000},
      {'name': 'Akko', 'latitude': 10.2833, 'longitude': 10.9667},
      {'name': 'Yamaltu', 'latitude': 10.3000, 'longitude': 11.2000},
      {'name': 'Deba', 'latitude': 10.2167, 'longitude': 11.3833},
    ],
    'Jigawa': [
      {'name': 'Dutse', 'latitude': 11.7000, 'longitude': 9.3333},
      {'name': 'Hadejia', 'latitude': 12.4500, 'longitude': 10.0333},
      {'name': 'Birnin Kudu', 'latitude': 11.4500, 'longitude': 9.4833},
      {'name': 'Gumel', 'latitude': 12.6333, 'longitude': 9.3833},
      {'name': 'Kazaure', 'latitude': 12.6500, 'longitude': 8.4167},
      {'name': 'Ringim', 'latitude': 12.1500, 'longitude': 9.1667},
      {'name': 'Babura', 'latitude': 12.7667, 'longitude': 9.0167},
      {'name': 'Garki', 'latitude': 12.4333, 'longitude': 9.1333},
      {'name': 'Maigatari', 'latitude': 12.8000, 'longitude': 9.4500},
      {'name': 'Kiyawa', 'latitude': 11.7833, 'longitude': 9.6167},
    ],
    'Nasarawa': [
      {'name': 'Lafia', 'latitude': 8.4833, 'longitude': 8.5167},
      {'name': 'Keffi', 'latitude': 8.8500, 'longitude': 7.8667},
      {'name': 'Akwanga', 'latitude': 8.9167, 'longitude': 8.4000},
      {'name': 'Nasarawa Town', 'latitude': 8.5333, 'longitude': 7.7000},
      {'name': 'Karu', 'latitude': 8.9833, 'longitude': 7.6167},
      {'name': 'Wamba', 'latitude': 8.9333, 'longitude': 8.6000},
      {'name': 'Doma', 'latitude': 8.3833, 'longitude': 8.3500},
      {'name': 'Toto', 'latitude': 8.3833, 'longitude': 7.0667},
      {'name': 'Eggon', 'latitude': 8.8000, 'longitude': 8.2833},
      {'name': 'Obi', 'latitude': 8.3667, 'longitude': 8.7667},
    ],
    'Taraba': [
      {'name': 'Jalingo', 'latitude': 8.8833, 'longitude': 11.3667},
      {'name': 'Wukari', 'latitude': 7.8667, 'longitude': 9.7833},
      {'name': 'Bali', 'latitude': 7.8500, 'longitude': 10.0167},
      {'name': 'Takum', 'latitude': 7.2667, 'longitude': 9.9833},
      {'name': 'Ibi', 'latitude': 8.1833, 'longitude': 9.7500},
      {'name': 'Mutum Biyu', 'latitude': 8.6333, 'longitude': 10.7667},
      {'name': 'Gembu', 'latitude': 6.7167, 'longitude': 11.2500},
      {'name': 'Zing', 'latitude': 8.9833, 'longitude': 11.7333},
      {'name': 'Lau', 'latitude': 9.2000, 'longitude': 11.2833},
      {'name': 'Serti', 'latitude': 7.5167, 'longitude': 11.3667},
    ],
    'Yobe': [
      {'name': 'Damaturu', 'latitude': 11.7500, 'longitude': 11.9667},
      {'name': 'Potiskum', 'latitude': 11.7167, 'longitude': 11.0667},
      {'name': 'Gashua', 'latitude': 12.8667, 'longitude': 11.0333},
      {'name': 'Nguru', 'latitude': 12.8833, 'longitude': 10.4500},
      {'name': 'Geidam', 'latitude': 12.8833, 'longitude': 11.9333},
      {'name': 'Buni Yadi', 'latitude': 11.2667, 'longitude': 12.0000},
      {'name': 'Goniri', 'latitude': 11.5000, 'longitude': 11.7000},
      {'name': 'Fika', 'latitude': 11.2833, 'longitude': 11.3000},
      {'name': 'Karasuwa', 'latitude': 12.7833, 'longitude': 10.8333},
      {'name': 'Yusufari', 'latitude': 13.0667, 'longitude': 11.1667},
    ],
  };

  /// Search for a location by coordinates (reverse geocoding).
  /// Returns the closest matching location name, or null if no match found.
  static Map<String, dynamic>? searchByCoordinates(double latitude, double longitude) {
    // Tolerance: within ~5km (0.05 degrees)
    const tolerance = 0.05;

    // Search towns first
    for (final entry in townsByState.entries) {
      final stateName = entry.key;
      for (final town in entry.value) {
        final lat = town['latitude'] as double;
        final lng = town['longitude'] as double;
        if ((lat - latitude).abs() <= tolerance && (lng - longitude).abs() <= tolerance) {
          return {
            'name': town['name'],
            'state': stateName,
            'latitude': lat,
            'longitude': lng,
            'type': 'town',
            'displayName': '${town['name']}, ${getStateDisplayName(stateName)}',
          };
        }
      }
    }

    // Search state capitals
    for (final state in states) {
      final lat = state['latitude'] as double;
      final lng = state['longitude'] as double;
      if ((lat - latitude).abs() <= tolerance && (lng - longitude).abs() <= tolerance) {
        return {
          'name': state['capital'],
          'state': state['name'],
          'latitude': lat,
          'longitude': lng,
          'type': 'state_capital',
          'displayName': '${state['capital']}, ${getStateDisplayName(state['name'])}',
        };
      }
    }

    return null;
  }
}