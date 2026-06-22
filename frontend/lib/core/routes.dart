import 'package:flutter/material.dart';

import '../modules/auth/screens/splash_screen.dart';
import '../modules/auth/screens/permission_screen.dart';
import '../modules/auth/screens/login_screen.dart';
import '../modules/auth/screens/forgot_password_screen.dart';
import '../modules/auth/screens/reset_password_screen.dart';
import '../modules/auth/screens/delete_account_screen.dart';
import '../modules/sos/screens/dashboard_screen.dart';
import '../modules/sos/screens/sos_screen.dart';
import '../modules/sos/screens/inbox_screen.dart';
import '../modules/sos/screens/offline_resources_screen.dart';
import '../modules/sos/screens/first_aid_screen.dart';
import '../modules/sos/screens/profile_screen.dart';
import '../modules/sos/screens/help_screen.dart';
import '../modules/sos/screens/settings_screen.dart';
import '../modules/sos/screens/emergency_contacts_screen.dart';
import '../modules/sos/screens/incident_report_screen.dart';
import '../modules/sos/screens/zone_details_screen.dart';
import '../modules/sos/screens/message_detail_screen.dart';
import '../modules/sos/screens/broadcast_screen.dart';
import '../modules/sos/screens/create_broadcast_screen.dart';
import '../modules/sos/screens/safe_route_screen.dart';
import '../modules/sos/screens/tip_off_screen.dart';
import '../modules/sos/screens/tip_review_screen.dart';
import '../modules/sos/screens/radio_broadcast_screen.dart';
import '../modules/sos/screens/walkie_talkie_monitor_screen.dart';
import '../modules/sos/screens/privacy_policy_screen.dart';
import '../modules/sos/screens/how_to_use_screen.dart';
import '../modules/maps/screens/map_screen.dart';
import '../modules/mesh/screens/mesh_status_screen.dart';
import '../modules/community/screens/community_feed_screen.dart';
import '../modules/community/screens/create_post_screen.dart';
import '../modules/community/screens/post_detail_screen.dart';
import '../modules/community/screens/user_posts_screen.dart';
import '../modules/community/screens/favorites_screen.dart';
import '../modules/community/screens/community_notifications_screen.dart';

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
  static const String firstAid = '/first-aid';
  static const String help = '/help';
  static const String settings = '/settings';
  static const String emergencyContacts = '/emergency-contacts';
  static const String incidentReport = '/incident-report';
  static const String zoneDetails = '/zone-details';
  static const String messageDetail = '/message-detail';
  static const String broadcasts = '/broadcasts';
  static const String createBroadcast = '/create-broadcast';
  static const String safeRoute = '/safe-route';
  static const String tipOff = '/tip-off';
  static const String tipReview = '/tip-review';
  static const String radioBroadcast = '/radio-broadcast';
  static const String walkieTalkieMonitor = '/walkie-talkie-monitor';

  // Community routes
  static const String communityFeed = '/community';
  static const String communityCreatePost = '/community/create';
  static const String communityPostDetail = '/community/post';
  static const String communityMyPosts = '/community/my-posts';
  static const String communityFavorites = '/community/favorites';
  static const String communityNotifications = '/community/notifications';

  // Store Compliance routes
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String deleteAccount = '/delete-account';
  static const String privacyPolicy = '/privacy-policy';
  static const String howToUse = '/how-to-use';

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
      case firstAid:
        return MaterialPageRoute(
          builder: (_) => const FirstAidScreen(),
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
      case AppRoutes.settings:
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
      case broadcasts:
        return MaterialPageRoute(
          builder: (_) => const BroadcastScreen(),
          settings: settings,
        );
      case createBroadcast:
        return MaterialPageRoute(
          builder: (_) => const CreateBroadcastScreen(),
          settings: settings,
        );
      case safeRoute:
        return MaterialPageRoute(
          builder: (_) => const SafeRouteScreen(),
          settings: settings,
        );
      case tipOff:
        return MaterialPageRoute(
          builder: (_) => const TipOffScreen(),
          settings: settings,
        );
      case tipReview:
        return MaterialPageRoute(
          builder: (_) => const TipReviewScreen(),
          settings: settings,
        );
      case radioBroadcast:
        return MaterialPageRoute(
          builder: (_) => const RadioBroadcastScreen(),
          settings: settings,
        );
      case walkieTalkieMonitor:
        return MaterialPageRoute(
          builder: (_) => const WalkieTalkieMonitorScreen(),
          settings: settings,
        );
      case communityFeed:
        return MaterialPageRoute(
          builder: (_) => const CommunityFeedScreen(),
          settings: settings,
        );
      case communityCreatePost:
        return MaterialPageRoute(
          builder: (_) => const CreatePostScreen(),
          settings: settings,
        );
      case communityPostDetail:
        final postId = settings.arguments as String? ?? '';
        return MaterialPageRoute(
          builder: (_) => PostDetailScreen(postId: postId),
          settings: settings,
        );
      case communityMyPosts:
        return MaterialPageRoute(
          builder: (_) => const UserPostsScreen(),
          settings: settings,
        );
      case communityFavorites:
        return MaterialPageRoute(
          builder: (_) => const FavoritesScreen(),
          settings: settings,
        );
      case communityNotifications:
        return MaterialPageRoute(
          builder: (_) => const CommunityNotificationsScreen(),
          settings: settings,
        );
      case forgotPassword:
        return MaterialPageRoute(
          builder: (_) => const ForgotPasswordScreen(),
          settings: settings,
        );
      case resetPassword:
        final token = settings.arguments as String? ?? '';
        return MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(token: token),
          settings: settings,
        );
      case deleteAccount:
        return MaterialPageRoute(
          builder: (_) => const DeleteAccountScreen(),
          settings: settings,
        );
      case privacyPolicy:
        return MaterialPageRoute(
          builder: (_) => const PrivacyPolicyScreen(),
          settings: settings,
        );
      case howToUse:
        return MaterialPageRoute(
          builder: (_) => const HowToUseScreen(),
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
