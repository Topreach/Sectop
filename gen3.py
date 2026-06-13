#!/usr/bin/env python3
import os, re
D=os.path.dirname(__file__)
P1=os.path.join(D,'frontend/lib/core/localization_part1.dart')
OUT=os.path.join(D,'frontend/lib/core/localization.dart')
with open(P1,'r',encoding='utf-8-sig')as f:c=f.read()
# Fix truncated line
c=c.replace("'please_enter_phone': 'J\u1ecdw\u1ecd t","'please_enter_phone': 'J\u1ecdw\u1ecd t\u1eb9 n\u1ecdmba foonu r\u1eb9 sii',")
L=c.split('\n')
# Find yo section start
yo_start=-1
for i,l in enumerate(L):
    if "'yo':" in l:
        yo_start=i
        break
# The file is truncated - use all lines up to the end (minus the fixed truncated line)
# The yo section doesn't close because the file is cut off
# We need to find where the yo section content ends (the last line with a key-value pair)
last_kv=yo_start
for i in range(yo_start+1, len(L)):
    if re.match(r"\s+'[^']+':\s'", L[i]):
        last_kv=i
# Base content: everything from start up to and including the last valid yo key-value line
base_lines=L[:last_kv+1]
# Get English keys (deduplicated)
ek=[];ie=False;ed=0;ek_set=set()
for l in L:
    if "'en':" in l:ie=True
    if ie:
        ed+=l.count('{')-l.count('}')
        m=re.match(r"\s+'([^']+)':\s'",l)
        if m and m.group(1) not in ek_set:
            ek.append(m.group(1))
            ek_set.add(m.group(1))
        if ed<=0:break
# Get existing yo keys
yk=set();iy=False;yd=0
for l in L:
    if "'yo':" in l:iy=True
    if iy:
        yd+=l.count('{')-l.count('}')
        m=re.match(r"\s+'([^']+)':\s'",l)
        if m:yk.add(m.group(1))
        if yd<=0:break
mk=[k for k in ek if k not in yk]
print(f"en={len(ek)} yo_existing={len(yk)} missing={len(mk)} yo_start={yo_start} last_kv={last_kv}")
def q(s):return "'"+s+"'"
def kv(k,v):return f"        {q(k)}: {q(v)},"
# Yoruba missing translations
yo={}
yo['please_enter_password']='J\u1ecdw\u1ecd t\u1eb9 \u1ecdr\u1ecdm\u1ecdm\u1ecd as\u1ecdp\u1ecd r\u1eb9 sii'
yo['password_min_chars']='\u1eccr\u1ecdm\u1ecdm\u1ecd as\u1ecdp\u1ecd gb\u1ecdd\u1ecdd\u1ecdd k\u1ecd \u00f3 k\u00e9r\u1eb9 sii ju \u00e0\u1e63\u1eb9 8'
yo['emergency_tools']='Aw\u1ecdn irin\u1e63\u1eb9 pajawiri'
yo['broadcasts']='Aw\u1ecdn igbohunsafefe'
yo['radio']='Redio'
yo['data_sync']='Amu\u1e63i\u1e63i data'
yo['syncing']='\u00ccm\u00fa\u1e63i\u1e63i'
yo['pending_items']='Aw\u1ecdn nkan ti o nduro'
yo['peers_connected']='Aw\u1ecdn \u1eb9l\u1eb9gb\u1eb9 ti a sop\u1ecd'
yo['sos_sent_silently']='SOS ti firan\u1e63\u1eb9 ni \u1ecdpal\u1ecdl\u1ecd'
yo['sos_failed']='SOS kuna'
yo['send_sos_alert_title']='Firan\u1e63\u1eb9 itaniji SOS'
yo['alert_type']='Iru itaniji'
yo['select_alert_type']='Yan iru itaniji'
yo['description_optional']='Apejuwe (a\u1e63ayan)'
yo['capture_evidence_optional']='Gba \u1eb9ri (a\u1e63ayan)'
yo['photo']='F\u1ecdt\u1ecd'
yo['video']='Fidio'
yo['audio']='Ohun'
yo['sending_in_seconds']='Firan\u1e63\u1eb9 ni {} aaya'
yo['tap_to_send_alert']='T\u1eb9 lati firan\u1e63\u1eb9 itaniji'
yo['ai_analyzing']='AI n \u1e63e itupal\u1eb9...'
yo['distress_detected']='Wahala ti a rii'
yo['no_distress_detected']='Ko si wahala ti a rii'
yo['priority']='Pataki'
yo['confidence']='Igbagb\u1ecd'
yo['alert_broadcast_channels']='Aw\u1ecdn ikanni igbohunsafefe itaniji'
yo['your_location_sent']='Ipo r\u1eb9 ti firan\u1e63\u1eb9'
yo['failed_to_send_sos']='Kuna lati firan\u1e63\u1eb9 SOS'
yo['permissions_required']='Aw\u1ecdn igbanilaaye ti a beere'
yo['location']='Ipo'
yo['bluetooth']='Bluetooth'
yo['storage']='Ibi ipam\u1ecd'
yo['unread_messages']='Aw\u1ecdn ifiran\u1e63\u1eb9 ti a ko ka'
yo['active_alerts']='Aw\u1ecdn itaniji ti n\u1e63i\u1e63e l\u1ecdw\u1ecd'
yo['recent_messages']='Aw\u1ecdn ifiran\u1e63\u1eb9 aip\u1eb9'
yo['no_recent_messages']='Ko si aw\u1ecdn ifiran\u1e63\u1eb9 aip\u1eb9'
yo['open_inbox']='\u1e62ii apoti ifiran\u1e63\u1eb9'
yo['unknown_sender']='Olufiran\u1e63\u1eb9 aim\u1ecd'
yo['medical_info']='Alaye i\u1e63oogun'
yo['privacy_security']='A\u1e63iri ati Aabo'
yo['stealth_mode_sos']='Ipo SOS ni ikoko'
yo['silent_panic_trigger']='Ik\u1ecdl\u1ecd \u1ecdpal\u1ecdl\u1ecd'
yo['stealth_mode_description']='Ipo ikoko n gba \u1ecd laaye lati firan\u1e63\u1eb9 itaniji laisi \u1e63i\u1e63i apoti ifiran\u1e63\u1eb9'
yo['close']='Pa'
yo['save']='Fipam\u1ecd'
yo['name']='Oruk\u1ecd'
yo['phone']='Foonu'
yo['profile_updated']='Profaili ti imudojuiw\u1ecdn'
yo['medical_info_saved']='Alaye i\u1e63oogun ti fipam\u1ecd'
yo['blood_type']='Iru \u1eb9j\u1eb9'
yo['allergies']='Aw\u1ecdn aleji'
yo['medications']='Aw\u1ecdn oogun'
yo['medical_conditions']='Aw\u1ecdn ipo i\u1e63oogun'
yo['add_contact']='Fi olubas\u1ecdr\u1ecd kun'
yo['edit_contact']='\u1e62atunk\u1ecd olubas\u1ecdr\u1ecd'
yo['no_contacts']='Ko si aw\u1ecdn olubas\u1ecdr\u1ecd'
yo['read_privacy_policy']='Ka eto a\u1e63iri'
yo['open_full_map']='\u1e62ii maapu ni kikun'
yo['zones_nearby']='Aw\u1ecdn agbegbe nitosi'
yo['failed_to_load']='Kuna lati gbe'
yo['change_language']='Yi ede pada'
yo['english']='G\u1eb9\u0300\u1eb9\u0301s\u00ec'
yo['yoruba']='Yor\u00f9b\u00e1'
yo['igbo']='Igbo'
yo['hausa']='Hausa'
yo['trapped']='Id\u1eb9k\u00f9n'
yo['lost']='P\u00e0d\u00e1n\u00f9'
yo['structural_damage']='Ibaj\u1eb9 igbekal\u1eb9'
yo['other_emergency']='Pajawiri miiran'
yo['general_emergency']='Pajawiri gbogbogbo'
yo['silent_panic']='Ipay\u00e0 \u1ecdpal\u1ecdl\u1ecd'
yo['stealth_sos']='SOS ikoko'
yo['stealth_sos_dashboard']='SOS ikoko'
yo['emergency_user']='Olumulo pajawiri'
yo['offline_mode']='Ipo ais\u1ecdp\u1ecd'
yo['medical_info_title']='Alaye i\u1e63oogun'
yo['privacy_security_title']='A\u1e63iri ati Aabo'
yo['edit_profile_title']='\u1e62atunk\u1ecd profaili'
yo['emergency_contacts_title']='Aw\u1ecdn olubas\u1ecdr\u1ecd pajawiri'
yo['about_title']='Nipa'
yo['app_version']='\u1eb8ya ohun elo'
yo['sectop_description']='Sectop j\u1eb9 ohun elo aabo agbegbe ti o fun \u1ecd laaye lati gba aw\u1ecdn itaniji ati aw\u1ecdn imudojuiw\u1ecdn lori aw\u1ecdn irokeke ewu'
yo['no_emergency_contacts']='Ko si aw\u1ecdn olubas\u1ecdr\u1ecd pajawiri'
yo['add_contact_title']='Fi olubas\u1ecdr\u1ecd kun'
yo['edit_contact_title']='\u1e62atunk\u1ecd olubas\u1ecdr\u1ecd'
yo['contact_name']='Oruk\u1ecd olubas\u1ecdr\u1ecd'
yo['contact_phone']='Foonu olubas\u1ecdr\u1ecd'
yo['save_contact']='Fipam\u1ecd olubas\u1ecdr\u1ecd'
yo['cancel_btn']='Fagilee'
yo['close_btn']='Pa'
yo['save_btn']='Fipam\u1ecd'
yo['cancel_action']='Fagilee'
yo['close_action']='Pa'
yo['save_action']='Fipam\u1ecd'
yo['permission_location']='Ipo'
yo['permission_notifications']='Aw\u1ecdn ifitonileti'
yo['permission_bluetooth']='Bluetooth'
yo['permission_storage']='Ibi ipam\u1ecd'
# Build output - start with base content (all lines up to last valid yo kv line)
out='\n'.join(base_lines)
# Add missing yo keys
for k in mk:
    if k in yo:
        out+='\n'+kv(k,yo[k])
# Close yo section (no trailing comma on last item - the kv() already adds comma)
out+='\n      },'
# Add ig section
out+="\n      'ig': {"
for i,k in enumerate(ek):
    comma=',' if i<len(ek)-1 else ''
    out+=f"\n        {q(k)}: {q(k.replace('_',' ').title())}{comma}"
out+='\n      },'
# Add ha section
out+="\n      'ha': {"
for i,k in enumerate(ek):
    comma=',' if i<len(ek)-1 else ''
    out+=f"\n        {q(k)}: {q(k.replace('_',' ').title())}{comma}"
out+='\n      },'
# Close _localeMap
out+='\n    };'
# Add translate() method inside the class
out+='\n\n  String translate(String key) {'
out+="\n    return _localizedStrings[locale.languageCode]?[key] ?? key;"
out+='\n  }'
# Close the AppLocalizations class
out+='\n}'
# Add delegate class (OUTSIDE the class)
out+='\n\nclass _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {'
out+="\n  const _AppLocalizationsDelegate();"
out+="\n  @override\n  bool isSupported(Locale locale) => ['en','yo','ig','ha'].contains(locale.languageCode);"
out+="\n  @override\n  Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale);"
out+="\n  @override\n  bool shouldReload(_AppLocalizationsDelegate old) => false;\n}"
# Add extension (OUTSIDE the class)
out+="\n\nextension AppLocalizationsX on BuildContext {"
out+="\n  AppLocalizations get loc => AppLocalizations.of(this);"
out+="\n  String tr(String key) => loc.translate(key);\n}"
out+='\n'
with open(OUT,'w',encoding='utf-8')as f:f.write(out)
sz=os.path.getsize(OUT)
print(f"Done. Size: {sz} bytes, Lines: {out.count(chr(10))}")
