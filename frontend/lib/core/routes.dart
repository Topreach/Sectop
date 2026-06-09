import 'package:flutter/material.dart';

import '../modules/auth/screens/splash_screen.dart';
import '../modules/auth/screens/permission_screen.dart';
import '../modules/auth/screens/login_screen.dart';
import '../modules/sos/screens/dashboard_screen.dart';
import '../modules/sos/screens/sos_screen.dart';
import '../modules/sos/screens/inbox_screen.dart';
import '../modules/sos/screens/offline_resources_screen.dart';
import '../modules/sos/screens/profile_screen.dart';
import '../modules/sos/screens/help_screen.dart';
import '../modules/sos/screens/settings_screen.dart';
import '../modules/sos/screens/emergency_contacts_screen.dart';
import '../modules/sos/screens/incident_report_screen.dart';
import '../modules/sos/screens/zone_details_screen.dart';
import '../modules/sos/screens/message_detail_screen.dart';
import '../modules/maps/screens/map_screen.dart';
import '../modules/mesh/screens/mesh_status_screen.dart';

/// Route names for the Danger Emergence System.
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String permissions = '/permissions';
  static const String login = '/login';
  static const String dashboard = '/dashboard';
  static const String sos = '/sos';
  static const String map = '/map';
  static const String inbox = '/inbox';
  static const String profile = '/profile';
  static const String meshStatus = '/mesh-status';
  static const String offlineResources = '/offline-resources';
  static const String help = '/help';
  static const String settings = '/settings';
  static const String emergencyContacts = '/emergency-contacts';
  static const String incidentReport = '/incident-report';
  static const String zoneDetails = '/zone-details';
  static const String messageDetail = '/message-detail';

  /// Generate the route generator for MaterialApp.
  static Route<dynamic>? generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: settings,
        );
      case permissions:
        return MaterialPageRoute(
          builder: (_) => const PermissionScreen(),
          settings: settings,
        );
      case login:
        return MaterialPageRoute(
          builder: (_) => const LoginScreen(),
          settings: settings,
        );
      case dashboard:
        return MaterialPageRoute(
          builder: (_) => const DashboardScreen(),
          settings: settings,
        );
      case sos:
        return MaterialPageRoute(
          builder: (_) => const SOSScreen(),
          settings: settings,
        );
      case map:
        return MaterialPageRoute(
          builder: (_) => const MapScreen(),
          settings: settings,
        );
      case inbox:
        return MaterialPageRoute(
          builder: (_) => const InboxScreen(),
          settings: settings,
        );
      case meshStatus:
        return MaterialPageRoute(
          builder: (_) => const MeshStatusScreen(),
          settings: settings,
        );
      case offlineResources:
        return MaterialPageRoute(
          builder: (_) => const OfflineResourcesScreen(),
          settings: settings,
        );
      case profile:
        return MaterialPageRoute(
          builder: (_) => const ProfileScreen(),
          settings: settings,
        );
      case help:
        return MaterialPageRoute(
          builder: (_) => const HelpScreen(),
          settings: settings,
        );
      case settings:
        return MaterialPageRoute(
          builder: (_) => const SettingsScreen(),
          settings: settings,
        );
      case emergencyContacts:
        return MaterialPageRoute(
          builder: (_) => const EmergencyContactsScreen(),
          settings: settings,
        );
      case incidentReport:
        return MaterialPageRoute(
          builder: (_) => const IncidentReportScreen(),
          settings: settings,
        );
      case zoneDetails:
        return MaterialPageRoute(
          builder: (_) => const ZoneDetailsScreen(),
          settings: settings,
        );
      case messageDetail:
        return MaterialPageRoute(
          builder: (_) => const MessageDetailScreen(),
          settings: settings,
        );
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('Route not found: ${settings.name}'),
            ),
          ),
          settings: settings,
        );
    }
  }
}
