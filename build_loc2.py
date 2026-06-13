#!/usr/bin/env python3
"""Build complete localization.dart - compact version using data-driven generation."""
import os, json

D = os.path.dirname(__file__)
P1 = os.path.join(D, 'frontend', 'lib', 'core', 'localization_part1.dart')
OUT = os.path.join(D, 'frontend', 'lib', 'core', 'localization.dart')

with open(P1, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix truncated line
old = "'please_enter_phone': 'J\u1ecdw\u1ecd t"
new = "'please_enter_phone': 'J\u1ecdw\u1ecd t\u1eb9 n\u1ecdmba foonu r\u1eb9 sii',"
content = content.replace(old, new)

lines = content.split('\n')

# Find yo section end
yo_end = -1
depth = 0
yo_started = False
for i, l in enumerate(lines):
    if "'yo': {" in l:
        yo_started = True
    if yo_started:
        depth += l.count('{') - l.count('}')
        if depth <= 0:
            yo_end = i
            break

print(f"yo_end: {yo_end}")

# Get all English keys from the en section
en_keys = []
in_en = False
en_depth = 0
for l in lines:
    if "'en': {" in l:
        in_en = True
    if in_en:
        en_depth += l.count('{') - l.count('}')
        m = __import__('re').match(r"\s+'([^']+)':\s'", l)
        if m:
            en_keys.append(m.group(1))
        if en_depth <= 0:
            break

print(f"English keys: {len(en_keys)}")

# Get existing Yoruba keys
yo_keys_existing = set()
in_yo = False
yo_depth = 0
for l in lines:
    if "'yo': {" in l:
        in_yo = True
    if in_yo:
        yo_depth += l.count('{') - l.count('}')
        m = __import__('re').match(r"\s+'([^']+)':\s'", l)
        if m:
            yo_keys_existing.add(m.group(1))
        if yo_depth <= 0:
            break

# Keys missing from Yoruba
missing_yo = [k for k in en_keys if k not in yo_keys_existing]
print(f"Missing Yoruba keys: {len(missing_yo)}")

# Generate Yoruba translations for missing keys using rules
# Nigerian languages share some patterns
def yo_translate(key):
    t = {
        'please_enter_password': 'J\u1ecdw\u1ecd t\u1eb9 \u1ecdr\u1ecdm\u1ecdm\u1ecd as\u1ecdp\u1ecd r\u1eb9 sii',
        'password_min_chars': '\u1eccr\u1ecdm\u1ecdm\u1ecd as\u1ecdp\u1ecd gb\u1ecdd\u1ecdd\u1ecdd k\u1ecd \u00f3 k\u00e9r\u1eb9 sii ju \u00e0\u1e63\u1eb9 8',
        'emergency_tools': 'Aw\u1ecdn irin\u1e63\u1eb9 pajawiri',
        'broadcasts': 'Aw\u1ecdn igbohunsafefe',
        'radio': 'Redio',
        'data_sync': 'Amu\u1e63i\u1e63i data',
        'syncing': '\u00ccm\u00fa\u1e63i\u1e63i',
        'pending_items': 'Aw\u1ecdn nkan ti o nduro',
        'peers_connected': 'Aw\u1ecdn \u1eb9l\u1eb9gb\u1eb9 ti a sop\u1ecd',
        'sos_sent_silently': 'SOS ti firan\u1e63\u1eb9 ni \u1ecdpal\u1ecdl\u1ecd',
        'sos_failed': 'SOS kuna',
        'send_sos_alert_title': 'Firan\u1e63\u1eb9 itaniji SOS',
        'alert_type': 'Iru itaniji',
        'select_alert_type': 'Yan iru itaniji',
        'description_optional': 'Apejuwe (a\u1e63ayan)',
        'capture_evidence_optional': 'Gba \u1eb9ri (a\u1e63ayan)',
        'photo': 'F\u1ecdt\u1ecd',
        'video': 'Fidio',
        'audio': 'Ohun',
        'sending_in_seconds': 'Firan\u1e63\u1eb9 ni {} aaya',
        'tap_to_send_alert': 'T\u1eb9 lati firan\u1e63\u1eb9 itaniji',
        'ai_analyzing': 'AI n \u1e63e itupal\u1eb9...',
        'distress_detected': 'Wahala ti a rii',
        'no_distress_detected': 'Ko si wahala ti a rii',
        'priority': 'Pataki',
        'confidence': 'Igbagb\u1ecd',
        'alert_broadcast_channels': 'Aw\u1ecdn ikanni igbohunsafefe itaniji',
        'your_location_sent': 'Ipo r\u1eb9 ti firan\u1e63\u1eb9',
        'failed_to_send_sos': 'Kuna lati firan\u1e63\u1eb9 SOS',
        'permissions_required': 'Aw\u1ecdn igbanilaaye ti a beere',
        'location': 'Ipo',
        'bluetooth': 'Bluetooth',
        'storage': 'Ibi ipam\u1ecd',
        'unread_messages': 'Aw\u1ecdn ifiran\u1e63\u1eb9 ti a ko ka',
        'active_alerts': 'Aw\u1ecdn itaniji ti n\u1e63i\u1e63e l\u1ecdw\u1ecd',
        'recent_messages': 'Aw\u1ecdn ifiran\u1e63\u1eb9 aip\u1eb9',
        'no_recent_messages': 'Ko si aw\u1ecdn ifiran\u1e63\u1eb9 aip\u1eb9',
        'open_inbox': '\u1e62ii apoti ifiran\u1e63\u1eb9',
        'unknown_sender': 'Olufiran\u1e63\u1eb9 aim\u1ecd',
        'medical_info': 'Alaye i\u1e63oogun',
        'privacy_security': 'A\u1e63iri ati Aabo',
        'stealth_mode_sos': 'Ipo SOS ni ikoko',
        'silent_panic_trigger': 'Ik\u1ecdl\u1ecd \u1ecdpal\u1ecdl\u1ecd',
        'stealth_mode_description': 'Ipo ikoko n gba \u1ecd laaye lati firan\u1e63\u1eb9 itaniji laisi \u1e63i\u1e63i apoti ifiran\u1e63\u1eb9',
        'close': 'Pa',
        'save': 'Fipam\u1ecd',
        'name': 'Oruk\u1ecd',
        'phone': 'Foonu',
        'profile_updated': 'Profaili ti imudojuiw\u1ecdn',
        'medical_info_saved': 'Alaye i\u1e63oogun ti fipam\u1ecd',
        'blood_type': 'Iru \u1eb9j\u1eb9',
        'allergies': 'Aw\u1ecdn aleji',
        'medications': 'Aw\u1ecdn oogun',
        'medical_conditions': 'Aw\u1ecdn ipo i\u1e63oogun',
        'add_contact': 'Fi olubas\u1ecdr\u1ecd kun',
        'edit_contact': '\u1e62atunk\u1ecd olubas\u1ecdr\u1ecd',
        'no_contacts': 'Ko si aw\u1ecdn olubas\u1ecdr\u1ecd',
        'read_privacy_policy': 'Ka eto a\u1e63iri',
        'open_full_map': '\u1e62ii maapu ni kikun',
        'zones_nearby': 'Aw\u1ecdn agbegbe nitosi',
        'failed_to_load': 'Kuna lati gbe',
        'change_language': 'Yi ede pada',
        'english': 'G\u1eb9\u0300\u1eb9\u0301s\u00ec',
        'yoruba': 'Yor\u00f9b\u00e1',
        'igbo': 'Igbo',
        'hausa': 'Hausa',
        'trapped': 'Id\u1eb9k\u00f9n',
        'lost': 'P\u00e0d\u00e1n\u00f9',
        'structural_damage': 'Ibaj\u1eb9 igbekal\u1eb9',
        'other_emergency': 'Pajawiri miiran',
        'general_emergency': 'Pajawiri gbogbogbo',
        'silent_panic': 'Ipay\u00e0 \u1ecdpal\u1ecdl\u1ecd',
        'stealth_sos': 'SOS ikoko',
        'stealth_sos_dashboard': 'SOS ikoko',
        'emergency_user': 'Olumulo pajawiri',
        'offline_mode': 'Ipo ais\u1ecdp\u1ecd',
        'medical_info_title': 'Alaye i\u1e63oogun',
        'privacy_security_title': 'A\u1e63iri ati Aabo',
        'edit_profile_title': '\u1e62atunk\u1ecd profaili',
        'emergency_contacts_title': 'Aw\u1ecdn olubas\u1ecdr\u1ecd pajawiri',
        'about_title': 'Nipa',
        'app_version': '\u1eb8ya ohun elo',
        'sectop_description': 'Sectop j\u1eb9 ohun elo aabo agbegbe ti o fun \u1ecd laaye lati gba aw\u1ecdn itaniji ati aw\u1ecdn imudojuiw\u1ecdn lori aw\u1ecdn irokeke ewu',
        'no_emergency_contacts': 'Ko si aw\u1ecdn olubas\u1ecdr\u1ecd pajawiri',
        'add_contact_title': 'Fi olubas\u1ecdr\u1ecd kun',
        'edit_contact_title': '\u1e62atunk\u1ecd olubas\u1ecdr\u1ecd',
        'contact_name': 'Oruk\u1ecd olubas\u1ecdr\u1ecd',
        'contact_phone': 'Foonu olubas\u1ecdr\u1ecd',
        'save_contact': 'Fipam\u1ecd olubas\u1ecdr\u1ecd',
        'cancel_btn': 'Fagilee',
        'close_btn': 'Pa',
        'save_btn': 'Fipam\u1ecd',
        'cancel_action': 'Fagilee',
        'close_action': 'Pa',
        'save_action': 'Fipam\u1ecd',
        'permission_location': 'Ipo',
        'permission_notifications': 'Aw\u1ecdn ifitonileti',
        'permission_bluetooth': 'Bluetooth',
        'permission_storage': 'Ibi ipam\u1ecd',
    }
    return t.get(key, key.replace('_', ' ').title())

# Generate Igbo translations
def ig_translate(key):
    t = {
        'app_name': 'Sectop','ok': '\u1eccma','cancel': 'Kagbuo','loading': 'Na-ebugo...',
        'error': 'Njehie','success': '\u1eccma','retry': 'Nwa \u1ecdz\u1ecd','confirm': 'Kwenye',
        'delete': 'Hichap\u1ee5','edit': 'Dezie','settings': 'Nt\u1ecdala','help': 'Enyemaka',
        'about': 'Banyere','version': 'Mp\u1ee5ta','exit': 'P\u1ee5\u1ecd','back': 'Az\u1ee5',
        'next': 'Osote','submit': 'Nyefee','search': 'Ch\u1ecd\u1ecd','filter': 'Nyochaa',
        'sort': 'Hazie','refresh': 'Meghar\u1ecba','no_data': 'Enwegh\u1ecb data',
        'try_again': 'Nwa \u1ecdz\u1ecd','network_error': 'Njehie netw\u1ecdk',
        'server_error': 'Njehie sava','unknown_error': 'Njehie amagh\u1ecb',
        'timeout_error': 'Oge gw\u1ee5chara','offline': 'An\u1ecdgh\u1ecb n\u2019\u1ecbntanet\u1ecb',
        'online': 'N\u2019\u1ecbntanet\u1ecb','connecting': 'Na-ejik\u1ecd...','connected': 'Ejik\u1ecdr\u1ecd',
        'disconnected': 'Kewap\u1ee5r\u1ee5','login': 'Banye','register': 'Deba aha',
        'logout': 'P\u1ee5\u1ecd','email': 'Email','password': 'Okwuntughe',
        'phone_number': 'N\u1ecdmba ekwent\u1ecb','full_name': 'Aha zuru ezu','sign_in': 'Banye',
        'sign_up': 'Deba aha','forgot_password': 'Chefuru okwuntughe?',
        'reset_password': 'T\u1ee5ghar\u1ecba okwuntughe','new_password': 'Okwuntughe \u1ecdh\u1ee5r\u1ee5',
        'confirm_password': 'Kwenye okwuntughe','create_account': 'Mep\u1ee5ta aka\u1ee5nt\u1ee5',
        'already_have_account': 'Enweela aka\u1ee5nt\u1ee5?','dont_have_account': 'Enwegh\u1ecb aka\u1ee5nt\u1ee5?',
        'welcome_back': 'Nn\u1ecd\u1ecd','welcome_to_sectop': 'Nn\u1ecd\u1ecd na Sectop',
        'sos_alert': 'Nk\u1ecdt\u1ecb SOS','send_sos': 'Ziga SOS','sos_sent': 'Ezigala SOS',
        'sending_sos': 'Na-eziga SOS...','cancel_sos': 'Kagbuo SOS',
        'sos_countdown': 'SOS na-ag\u1ee5ta {}','emergency': 'Ihe mberede',
        'help_message': 'Ozi enyemaka','current_location': '\u1eccn\u1ecdd\u1ee5 ugbu a',
        'share_location': 'Kesaa \u1ecdn\u1ecdd\u1ee5','tracking': 'Na-eso',
        'stop_tracking': 'Kw\u1ee5s\u1ecb \u1ecbso','start_tracking': 'Malite \u1ecbso',
        'location_tracking': '\u1ecaso \u1ecdn\u1ecdd\u1ee5','location_permission': 'Ikike \u1ecdn\u1ecdd\u1ee5',
        'location_permission_desc': 'Sectop ch\u1ecdr\u1ecd ikike \u1ecdn\u1ecdd\u1ee5 iji zipu \u1ecdn\u1ecdd\u1ee5 g\u1ecb n\u2019ihe mberede',
        'enable_location': 'Gosi \u1ecdn\u1ecdd\u1ee5','enable_bluetooth': 'Gosi Bluetooth',
        'dashboard': 'Dashboard','inbox': 'Igbe ozi','map': 'Map','profile': 'Profa\u1ecbl\u1ee5',
        'home': '\u1ee4l\u1ecd','notifications': 'Ngosi','messages': 'Ozi','alerts': 'Nk\u1ecdt\u1ecb',
        'incidents': 'Ihe mere','report_incident': 'K\u1ecd\u1ecd ihe mere',
        'view_details': 'Le nk\u1ecdwa','status': '\u1eccn\u1ecdd\u1ee5','active': 'Na-ar\u1ee5 \u1ecdr\u1ee5',
        'inactive': 'An\u1ecdgh\u1ecb \u1ecdr\u1ee5','pending': 'Na-echere','resolved': 'Edozila',
        'closed': 'Emechila','critical': 'D\u1ecb ok\u00e9 mkpa','high': 'Elu','medium': '\u1ecckara',
        'low': 'Ala','safe': 'Nchebe','danger': 'Ihe egwu','warning': '\u1ecad\u1ecd aka n\u00e1 nt\u1ecb',
        'info': 'Ozi','threat_level': '\u1ecckwa ihe egwu','threats_nearby': 'Ihe egwu d\u1ecb nso',
        'no_threats': 'Enwegh\u1ecb ihe egwu','safe_route': '\u1ee4z\u1ecd nchebe',
        'calculate_route': 'Gbak\u1ecd\u1ecd \u1ee5z\u1ecd','route_planned': 'Emebere \u1ee5z\u1ecd',
        'avoid_area': 'Zere mpaghara','danger_zone': 'Mpaghara ihe egwu',
        'restricted_area': 'Mpaghara amachibidoro','mesh_network': 'Netw\u1ecdk mesh',
        'mesh_status': '\u1eccn\u1ecdd\u1ee5 mesh','mesh_connected': 'Mesh ejik\u1ecdr\u1ecd',
        'mesh_disconnected': 'Mesh kewap\u1ee5r\u1ee5','mesh_peers': 'Nd\u1ecb \u1ecdz\u1ecdb\u1ecd mesh',
        'bluetooth_scanning': 'Nyocha Bluetooth','bluetooth_disabled': 'Eny\u1ecdr\u1ecd Bluetooth',
        'bluetooth_enabled': 'Gosiri Bluetooth','device_info': 'Ozi ngwa\u1ecdr\u1ee5',
        'device_id': 'NJ ngwa\u1ecdr\u1ee5','battery_level': '\u1ecckwa batr\u1ecb',
        'charging': 'Na-ach\u1ecd','not_charging': 'Anagh\u1ecb ach\u1ecd',
        'last_seen': '\u1ee4b\u1ecdcch\u1ecb ikpeaz\u1ee5','online_users': 'Nd\u1ecb \u1ecdr\u1ee5 n\u2019\u1ecbntanet\u1ecb',
        'offline_users': 'Nd\u1ecb \u1ecdr\u1ee5 an\u1ecdgh\u1ecb n\u2019\u1ecbntanet\u1ecb','tip_off': 'Nt\u1ee5nye',
        'send_tip': 'Ziga nt\u1ee5nye','tip_sent': 'Ezigala nt\u1ee5nye',
        'tip_anonymous': 'Nt\u1ee5nye na-amagh\u1ecb aha','tip_off_title': 'Nt\u1ee5nye nchebe',
        'tip_description': 'K\u1ecd\u1ecd ihe enyo enyo n\u2019enwegh\u1ecb egwu',
        'tip_off_guidelines': 'Ntuziaka nt\u1ee5nye','anonymous': 'Amagh\u1ecb aha',
        'your_identity_protected': 'A ga-echebe njirimara g\u1ecb','broadcast': 'Mgbasa ozi',
        'create_broadcast': 'Mep\u1ee5ta mgbasa ozi','broadcast_message': 'Ozi mgbasa ozi',
        'broadcast_to': 'Mgbasa ozi na','select_state': 'H\u1ecdr\u1ecd steeti',
        'select_lga': 'H\u1ecdr\u1ecd LGA','all_states': 'Steeti niile','all_lgas': 'LGA niile',
        'target_audience': 'Nd\u1ecb na-ege nt\u1ecb','send_broadcast': 'Ziga mgbasa ozi',
        'broadcast_history': 'Ak\u1ee5k\u1ecd mgbasa ozi','no_broadcasts': 'Enwegh\u1ecb mgbasa ozi',
        'walkie_talkie': 'Walkie-talkie','press_to_talk': 'P\u1ecba ikwu okwu',
        'release_to_send': 'Hap\u1ee5 iziga','recording': 'Na-edek\u1ecd...',
        'voice_message': 'Ozi olu','voice_broadcast': 'Mgbasa ozi olu',
        'first_aid': 'Enyemaka mb\u1ee5','first_aid_guide': 'Ntuziaka enyemaka mb\u1ee5',
        'first_aid_tips': 'Nd\u1ee5m\u1ecdd\u1ee5 enyemaka mb\u1ee5','emergency_numbers': 'N\u1ecdmba mberede',
        'call_emergency': 'Kp\u1ecd\u1ecd mberede','police': 'Nd\u1ecb uwe ojii',
        'fire_service': '\u1eccr\u1ee5 \u1ecdk\u1ee5','ambulance': '\u1ee4gb\u1ecd ihe mberede',
        'nema': 'NEMA','frsc': 'FRSC','custom_emergency': 'Mberede ahaziri',
        'add_number': 'Tinye n\u1ecdmba','edit_number': 'Dezie n\u1ecdmba',
        'remove_number': 'Wep\u1ee5 n\u1ecdmba','default_emergency': 'Mberede ndabara',
        'sectop_community': 'Obodo Sectop','community': 'Obodo','forum': '\u1eccgbak\u1ecd',
        'discussions': 'Mkpar\u1ecbta \u1ee5ka','post': 'Zipu','comment': 'Okwu',
        'share': 'Kesaa','report': 'K\u1ecd\u1ecd','block_user': 'Gbochie onye \u1ecdr\u1ee5',
        'mute': 'Gbachi nk\u1ecbt\u1ecb','unmute': 'Wep\u1ee5 \u1ecbgbachi nk\u1ecbt\u1ecb',
        'follow': 'Soro','unfollow': 'Kw\u1ee5s\u1ecb \u1ecbs\u1ecd','verified': 'Enyochala',
        'official': 'G\u1ecd\u1ecdmenti','trusted_source': 'Isi iyi a t\u1ee5kwas\u1ecbr\u1ecb obi',
        'ai_powered': 'Nke AI kwadoro','threat_analysis': 'Nyocha ihe egwu',
        'analyzing': 'Na-enyocha...','threat_detected': 'Ach\u1ecdp\u1ee5tala ihe egwu',
        'no_threat_detected': 'Ach\u1ecdp\u1ee5tagh\u1ecb ihe egwu','safe_area': 'Mpaghara nchebe',
        'evacuation_route': '\u1ee4z\u1ecd mgbap\u1ee5','shelter_in_place': 'Gbachi ebe ah\u1ee5',
        'emergency_alerts': 'Nk\u1ecdt\u1ecb mberede','subscribe_alerts': 'Denye aha maka nk\u1ecdt\u1ecb',
        'unsubscribe_alerts': 'Wep\u1ee5 aha na nk\u1ecdt\u1ecb','alert_history': 'Ak\u1ee5k\u1ecd nk\u1ecdt\u1ecb',
        'clear_alerts': 'Kpochap\u1ee5 nk\u1ecdt\u1ecb','mark_all_read': 'Gosi na ag\u1ee5la ha niile',
        'no_alerts': 'Enwegh\u1ecb nk\u1ecdt\u1ecb','account': 'Aka\u1ee5nt\u1ee5',
        'account_settings': 'Nt\u1ecdala aka\u1ee5nt\u1ee5','privacy_policy': 'Am\u1ee5ma nzuzo',
        'terms_of_service': 'Usoro \u1ecdr\u1ee5','delete_account': 'Hichap\u1ee5 aka\u1ee5nt\u1ee5',
        'delete_account_warning': '\u1ecc ga-efunah\u1ee5 data g\u1ecb niile. Enwegh\u1ecb ike \u1ecbt\u1ee5ghar\u1ecba omume a.',
        'confirm_delete': 'Kwenye ihichap\u1ee5','account_deleted': 'Emechara hichap\u1ee5 aka\u1ee5nt\u1ee5',
        'data_saved_offline': 'Echekwara data na mp\u1ee5ga','sync_now': 'Mek\u1ecdr\u1ecbta ugbu a',
        'last_sync': 'Mek\u1ecdr\u1ecbta ikpeaz\u1ee5','sync_status': '\u1eccn\u1ecdd\u1ee5 mmek\u1ecdr\u1ecbta',
        'sync_complete': 'Mek\u1ecdr\u1ecbtachara','sync_failed': 'Mmek\u1ecdr\u1ecbta dara',
        'sync_in_progress': 'Mmek\u1ecdr\u1ecbta na-aga n\u2019ihu',
        'please_enter_phone': 'Biko tinye n\u1ecdmba ekwent\u1ecb g\u1ecb',
        'please_enter_password': 'Biko tinye okwuntughe g\u1ecb',
        'password_min_chars': 'Okwuntughe ga-enwe opekata mpe mkp\u1ee5r\u1ee5edemede 8',
        'emergency_tools': 'Ngwa\u1ecdr\u1ee5 mberede','broadcasts': 'Mgbasa ozi',
        'radio': 'Redio','data_sync': 'Mmek\u1ecdr\u1ecbta data','syncing': 'Na-emek\u1ecdr\u1ecbta',
        'pending_items': 'Ihe nd\u1ecb na-echere','peers_connected': 'Nd\u1ecb \u1ecdz\u1ecdb\u1ecd ejik\u1ecdr\u1ecd',
        'sos_sent_silently': 'Ezigara SOS na nk\u1ecbt\u1ecb','sos_failed': 'SOS dara',
        'send_sos_alert_title': 'Ziga nk\u1ecdt\u1ecb SOS','alert_type': '\u1ee4d\u1ecb nk\u1ecdt\u1ecb',
        'select_alert_type': 'H\u1ecdr\u1ecd \u1ee5d\u1ecb nk\u1ecdt\u1ecb',
        'description_optional': 'Nk\u1ecdwa (nh\u1ecdr\u1ecd)',
        'capture_evidence_optional': 'Jide ihe akaebe (nh\u1ecdr\u1ecd)','photo': 'Foto',
        'video': 'Vidiyo','audio': '\u1eccd\u1ecbyo','sending_in_seconds': 'Na-eziga na {} sek\u1ecdnnd',
        'tap_to_send_alert': 'P\u1ecba iziga nk\u1ecdt\u1ecb','ai_analyzing': 'AI na-enyocha...',
        'distress_detected': 'Ach\u1ecdp\u1ee5tala nsogbu','no_distress_detected': 'Ach\u1ecdp\u1ee5tagh\u1ecb nsogbu',
        'priority': 'Mkpa','confidence': 'Nt\u1ee5kwas\u1ecb obi',
        'alert_broadcast_channels': '\u1eccwa mgbasa ozi nk\u1ecdt\u1ecb',
        'your_location_sent': 'Ezigala \u1ecdn\u1ecdd\u1ee5 g\u1ecb','failed_to_send_sos': '\u1ecc dara iziga SOS',
        'permissions_required': 'Ikike ach\u1ecdr\u1ecd','location': '\u1eccn\u1ecdd\u1ee5',
        'bluetooth': 'Bluetooth','storage': 'Nchekwa','unread_messages': 'Ozi ag\u1ee5gh\u1ecb',
        'active_alerts': 'Nk\u1ecdt\u1ecb na-ar\u1ee5 \u1ecdr\u1ee5','recent_messages': 'Ozi na-ad\u1ecbbegh\u1ecb anya',
        'no_recent_messages': 'Enwegh\u1ecb ozi na-ad\u1ecbbegh\u1ecb anya','open_inbox': 'Mepee igbe ozi',
        'unknown_sender': 'Onye zitere amagh\u1ecb','medical_info': 'Ozi ah\u1ee5ike',
        'privacy_security': 'Nzuzo na Nchebe','stealth_mode_sos': 'SOS \u1ecdn\u1ecdd\u1ee5 nzuzo',
        'silent_panic_trigger': 'Mkpasu iwe \u1ecbgbachi nk\u1ecbt\u1ecb',
        'stealth_mode_description': '\u1eccn\u1ecdd\u1ee5 nzuzo na-enye g\u1ecb ohere iziga nk\u1ecdt\u1ecb n\u2019ezogh\u1ecb \u1ecdn\u1ee5',
        'close': 'Mechie','save': 'Chekwa','name': 'Aha','phone': 'Ekwent\u1ecb',
        'profile_updated': 'Emechap\u1ee5ta profa\u1ecbl\u1ee5','medical_info_saved': 'Echekwala ozi ah\u1ee5ike',
        'blood_type': '\u1ee4d\u1ecb \u1ecdbara','allergies': 'Ihe nf\u1ee5kas\u1ecb ah\u1ee5',
        'medications': '\u1eccgw\u1ee5','medical_conditions': '\u1eccn\u1ecdd\u1ee5 ah\u1ee5ike',
        'add_contact': 'Tinye k\u1ecdntakt\u1ecb','edit_contact': 'Dezie k\u1ecdntakt\u1ecb',
        'no_contacts': 'Enwegh\u1ecb k\u1ecdntakt\u1ecb','read_privacy_policy': 'G\u1ee5\u1ecd am\u1ee5ma nzuzo',
        'open_full_map': 'Mepee map zuru ezu','zones_nearby': 'Mpaghara d\u1ecb nso',
        'failed_to_load': '\u1ecc dara ibunye','change_language': 'Gbanwee as\u1ee5s\u1ee5',
        'english': 'Bekee','yoruba': 'Yoruba','igbo': 'Igbo','hausa': 'Hausa',
        'trapped': 'T\u1ecdr\u1ecd at\u1ecd','lost': 'Furfu','structural_damage': 'Mmebi ihe owuwu',
        'other_emergency': 'Ihe mberede \u1ecdz\u1ecd','general_emergency': 'Ihe mberede izugbe',
        'silent_panic': '\u1ee4j\u1ecd \u1ecbgbachi nk\u1ecbt\u1ecb','stealth_sos': 'SOS nzuzo',
        'stealth_sos_dashboard': 'SOS nzuzo','emergency_user': 'Onye \u1ecdr\u1ee5 mberede',
        'offline_mode': '\u1eccn\u1ecdd\u1ee5 an\u1ecdgh\u1ecb n\u2019\u1ecbntanet\u1ecb',
        'medical_info_title': 'Ozi ah\u1ee5ike','privacy_security_title': 'Nzuzo na Nchebe',
        'edit_profile_title': 'Dezie profa\u1ecbl\u1ee5','emergency_contacts_title': 'K\u1ecdntakt\u1ecb mberede',
        'about_title': 'Banyere','app_version': 'Mp\u1ee5ta ngwa',
        'sectop_description': 'Sectop b\u1ee5 ngwa nchebe obodo nke na-enye g\u1ecb ohere \u1ecbnata nk\u1ecdt\u1ecb na mmelite banyere ihe egwu nchebe',
        'no_emergency_contacts': 'Enwegh\u1ecb k\u1ecdntakt\u1ecb mberede',
        'add_contact_title': 'Tinye k\u1ecdntakt\u1ecb','edit_contact_title': 'Dezie k\u1ecdntakt\u1ecb',
        'contact_name': 'Aha k\u1ecdntakt\u1ecb','contact_phone': 'Ekwent\u1ecb k\u1ecdntakt\u1ecb',
        'save_contact': 'Chekwa k\u1ecdntakt\u1ecb','cancel_btn': 'Kagbuo','close_btn': 'Mechie',
        'save_btn': 'Chekwa','cancel_action': 'Kagbuo','close_action': 'Mechie',
        'save_action': 'Chekwa','permission_location': '\u1eccn\u1ecdd\u1ee5',
        'permission_notifications': 'Ngosi','permission_bluetooth': 'Bluetooth',
        'permission_storage': 'Nchekwa