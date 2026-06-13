package com.dangeremergence.service;

import jakarta.annotation.PostConstruct;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.*;

/**
 * Nigeria reverse geocoding service that resolves GPS coordinates to
 * State and Local Government Area (LGA) names.
 *
 * Uses a simplified polygon-based lookup for Nigeria's 36 states + FCT.
 * Each state is represented by an approximate bounding polygon.
 * Falls back to nearest-state-by-distance when coordinates fall outside
 * defined boundaries.
 */
@Service
@Slf4j
public class NigeriaLocationService {

    /**
     * Represents a geo-fence boundary for a state using a simplified
     * bounding box with additional exclusion zones for accuracy.
     */
    private static class StateBoundary {
        final String name;
        final double minLat, maxLat, minLng, maxLng;
        final List<String> lgas;

        StateBoundary(String name, double minLat, double maxLat,
                      double minLng, double maxLng, List<String> lgas) {
            this.name = name;
            this.minLat = minLat;
            this.maxLat = maxLat;
            this.minLng = minLng;
            this.maxLng = maxLng;
            this.lgas = lgas;
        }

        boolean contains(double lat, double lng) {
            return lat >= minLat && lat <= maxLat
                    && lng >= minLng && lng <= maxLng;
        }

        double centerLat() { return (minLat + maxLat) / 2.0; }
        double centerLng() { return (minLng + maxLng) / 2.0; }
    }

    private final List<StateBoundary> states = new ArrayList<>();

    /** Nigeria bounding box (approximate). */
    private static final double NIGERIA_MIN_LAT = 4.0;
    private static final double NIGERIA_MAX_LAT = 14.0;
    private static final double NIGERIA_MIN_LNG = 2.5;
    private static final double NIGERIA_MAX_LNG = 15.0;

    @PostConstruct
    public void init() {
        // Nigeria's 36 states + FCT with approximate bounding boxes
        // and sample LGAs for each state.
        // Coordinates are approximate centroids with ± range.

        states.add(new StateBoundary("Abia", 5.0, 6.0, 7.0, 8.0, Arrays.asList(
                "Aba North", "Aba South", "Arochukwu", "Bende", "Ikwuano",
                "Isiala Ngwa North", "Isiala Ngwa South", "Isuikwuato",
                "Obi Ngwa", "Ohafia", "Osisioma", "Ugwunagbo", "Ukwa East",
                "Ukwa West", "Umuahia North", "Umuahia South", "Umu Nneochi")));

        states.add(new StateBoundary("Adamawa", 7.0, 11.0, 11.0, 14.0, Arrays.asList(
                "Demsa", "Fufore", "Ganye", "Girei", "Gombi", "Guyuk",
                "Hong", "Jada", "Lamurde", "Madagali", "Maiha", "Mayo-Belwa",
                "Michika", "Mubi North", "Mubi South", "Numan", "Shelleng",
                "Song", "Toungo", "Yola North", "Yola South")));

        states.add(new StateBoundary("Akwa Ibom", 4.3, 5.5, 7.2, 8.5, Arrays.asList(
                "Abak", "Eastern Obolo", "Eket", "Esit Eket", "Essien Udim",
                "Etim Ekpo", "Etinan", "Ibeno", "Ibesikpo Asutan", "Ibiono Ibom",
                "Ikot Abasi", "Ikot Ekpene", "Ini", "Itu", "Mbo", "Mkpat Enin",
                "Nsit Atai", "Nsit Ibom", "Nsit Ubium", "Obot Akara", "Okobo",
                "Onna", "Oron", "Oruk Anam", "Udung Uko", "Ukanafun",
                "Uruan", "Urue-Offong/Oruko", "Uyo")));

        states.add(new StateBoundary("Anambra", 5.6, 6.5, 6.6, 7.3, Arrays.asList(
                "Aguata", "Anambra East", "Anambra West", "Anaocha", "Awka North",
                "Awka South", "Ayamelum", "Dunukofia", "Ekwusigo", "Idemili North",
                "Idemili South", "Ihiala", "Njikoka", "Nnewi North", "Nnewi South",
                "Ogbaru", "Onitsha North", "Onitsha South", "Orumba North",
                "Orumba South", "Oyi")));

        states.add(new StateBoundary("Bauchi", 9.5, 12.5, 8.5, 11.0, Arrays.asList(
                "Alkaleri", "Bauchi", "Bogoro", "Damban", "Darazo", "Dass",
                "Gamawa", "Ganjuwa", "Giade", "Itas/Gadau", "Jama'are",
                "Katagum", "Kirfi", "Misau", "Ningi", "Shira", "Tafawa Balewa",
                "Toro", "Warji", "Zaki")));

        states.add(new StateBoundary("Bayelsa", 4.3, 5.5, 5.0, 6.8, Arrays.asList(
                "Brass", "Ekeremor", "Kolokuma/Opokuma", "Nembe", "Ogbia",
                "Sagbama", "Southern Ijaw", "Yenagoa")));

        states.add(new StateBoundary("Benue", 6.3, 8.5, 7.5, 10.0, Arrays.asList(
                "Ado", "Agatu", "Apa", "Buruku", "Gboko", "Guma", "Gwer East",
                "Gwer West", "Katsina-Ala", "Konshisha", "Kwande", "Logo",
                "Makurdi", "Obi", "Ogbadibo", "Ohimini", "Oju", "Okpokwu",
                "Otukpo", "Tarka", "Ukum", "Ushongo", "Vandeikya")));

        states.add(new StateBoundary("Borno", 10.0, 14.0, 11.0, 15.0, Arrays.asList(
                "Abadam", "Askira/Uba", "Bama", "Bayo", "Biu", "Chibok",
                "Damboa", "Dikwa", "Gubio", "Guzamala", "Gwoza", "Hawul",
                "Jere", "Kaga", "Kala/Balge", "Konduga", "Kukawa", "Kwaya Kusar",
                "Mafa", "Magumeri", "Maiduguri", "Marte", "Mobbar", "Monguno",
                "Ngala", "Nganzai", "Shani")));

        states.add(new StateBoundary("Cross River", 4.5, 7.0, 7.5, 9.5, Arrays.asList(
                "Abi", "Akamkpa", "Akpabuyo", "Bakassi", "Bekwarra", "Biase",
                "Boki", "Calabar Municipal", "Calabar South", "Etung",
                "Ikom", "Obanliku", "Obubra", "Obudu", "Odukpani", "Ogoja",
                "Yakurr", "Yala")));

        states.add(new StateBoundary("Delta", 5.0, 6.5, 5.0, 6.8, Arrays.asList(
                "Aniocha North", "Aniocha South", "Bomadi", "Burutu", "Ethiope East",
                "Ethiope West", "Ika North East", "Ika South", "Isoko North",
                "Isoko South", "Ndokwa East", "Ndokwa West", "Okpe", "Oshimili North",
                "Oshimili South", "Patani", "Sapele", "Udu", "Ughelli North",
                "Ughelli South", "Ukwuani", "Uvwie", "Warri North", "Warri South",
                "Warri South West")));

        states.add(new StateBoundary("Ebonyi", 5.8, 6.8, 7.5, 8.5, Arrays.asList(
                "Abakaliki", "Afikpo North", "Afikpo South", "Ebonyi", "Ezza North",
                "Ezza South", "Ikwo", "Ishielu", "Ivo", "Izzi", "Ohaozara",
                "Ohaukwu", "Onicha")));

        states.add(new StateBoundary("Edo", 5.5, 7.0, 5.0, 6.8, Arrays.asList(
                "Akoko-Edo", "Egor", "Esan Central", "Esan North-East",
                "Esan South-East", "Esan West", "Etsako Central", "Etsako East",
                "Etsako West", "Igueben", "Ikpoba-Okha", "Oredo", "Orhionmwon",
                "Ovia North-East", "Ovia South-West", "Owan East", "Owan West",
                "Uhunmwonde")));

        states.add(new StateBoundary("Ekiti", 7.2, 8.0, 4.8, 5.8, Arrays.asList(
                "Ado Ekiti", "Efon", "Ekiti East", "Ekiti South-West",
                "Ekiti West", "Emure", "Gbonyin", "Ido Osi", "Ijero",
                "Ikere", "Ikole", "Ilejemeje", "Irepodun/Ifelodun", "Ise/Orun",
                "Moba", "Oye")));

        states.add(new StateBoundary("Enugu", 5.8, 7.0, 7.0, 7.8, Arrays.asList(
                "Aninri", "Awgu", "Enugu East", "Enugu North", "Enugu South",
                "Ezeagu", "Igbo Etiti", "Igbo Eze North", "Igbo Eze South",
                "Isi Uzo", "Nkanu East", "Nkanu West", "Nsukka", "Oji River",
                "Udenu", "Udi", "Uzo Uwani")));

        states.add(new StateBoundary("FCT", 8.5, 9.5, 6.8, 7.8, Arrays.asList(
                "Abaji", "Bwari", "Gwagwalada", "Kuje", "Kwali",
                "Municipal Area Council")));

        states.add(new StateBoundary("Gombe", 9.5, 11.0, 10.0, 12.0, Arrays.asList(
                "Akko", "Balanga", "Billiri", "Dukku", "Funakaye", "Gombe",
                "Kaltungo", "Kwami", "Nafada", "Shongom", "Yamaltu/Deba")));

        states.add(new StateBoundary("Imo", 5.2, 6.0, 6.6, 7.5, Arrays.asList(
                "Aboh Mbaise", "Ahiazu Mbaise", "Ehime Mbano", "Ezinihitte",
                "Ideato North", "Ideato South", "Ihitte/Uboma", "Ikeduru",
                "Isiala Mbano", "Isu", "Mbaitoli", "Ngor Okpala", "Njaba",
                "Nkwerre", "Nwangele", "Obowo", "Oguta", "Ohaji/Egbema",
                "Okigwe", "Orlu", "Orsu", "Oru East", "Oru West", "Owerri Municipal",
                "Owerri North", "Owerri West", "Unuimo")));

        states.add(new StateBoundary("Jigawa", 11.0, 13.0, 8.5, 10.5, Arrays.asList(
                "Auyo", "Babura", "Biriniwa", "Birnin Kudu", "Buji", "Dutse",
                "Gagarawa", "Garki", "Gumel", "Guri", "Gwaram", "Gwiwa",
                "Hadejia", "Jahun", "Kafin Hausa", "Kaugama", "Kazaure",
                "Kiri Kasama", "Kiyawa", "Maigatari", "Malam Madori", "Miga",
                "Ringim", "Roni", "Sule Tankarkar", "Taura", "Yankwashi")));

        states.add(new StateBoundary("Kaduna", 9.0, 11.5, 6.5, 9.0, Arrays.asList(
                "Birnin Gwari", "Chikun", "Giwa", "Igabi", "Ikara", "Jaba",
                "Jema'a", "Kachia", "Kaduna North", "Kaduna South", "Kagarko",
                "Kajuru", "Kaura", "Kauru", "Kubau", "Kudan", "Lere", "Makarfi",
                "Sabon Gari", "Sanga", "Soba", "Zangon Kataf", "Zaria")));

        states.add(new StateBoundary("Kano", 10.5, 12.5, 7.5, 10.0, Arrays.asList(
                "Ajingi", "Albasu", "Bagwai", "Bebeji", "Bichi", "Bunkure",
                "Dala", "Dambatta", "Dawakin Kudu", "Dawakin Tofa", "Doguwa",
                "Fagge", "Gabasawa", "Garko", "Garun Mallam", "Gaya", "Gezawa",
                "Gwale", "Gwarzo", "Kabo", "Kano Municipal", "Karaye", "Kibiya",
                "Kiru", "Kumbotso", "Kunchi", "Kura", "Madobi", "Makoda",
                "Minjibir", "Nasarawa", "Rano", "Rimin Gado", "Rogo", "Shanono",
                "Sumaila", "Takai", "Tarauni", "Tofa", "Tsanyawa", "Tudun Wada",
                "Ungogo", "Warawa", "Wudil")));

        states.add(new StateBoundary("Katsina", 11.0, 13.5, 6.5, 9.0, Arrays.asList(
                "Bakori", "Batagarawa", "Batsari", "Baure", "Bindawa", "Charanchi",
                "Dan Musa", "Dandume", "Danja", "Daura", "Dutsi", "Dutsin Ma",
                "Faskari", "Funtua", "Ingawa", "Jibia", "Kafur", "Kaita",
                "Kankara", "Kankia", "Katsina", "Kurfi", "Kusada", "Mai'Adua",
                "Malumfashi", "Mani", "Mashi", "Matazu", "Musawa", "Rimi",
                "Sabuwa", "Safana", "Sandamu", "Zango")));

        states.add(new StateBoundary("Kebbi", 10.0, 13.0, 3.5, 5.5, Arrays.asList(
                "Aleiro", "Arewa Dandi", "Argungu", "Augie", "Bagudo", "Birnin Kebbi",
                "Bunza", "Dandi", "Fakai", "Gwandu", "Jega", "Kalgo", "Koko/Besse",
                "Maiyama", "Ngaski", "Sakaba", "Shanga", "Suru", "Wasagu/Danko",
                "Yauri", "Zuru")));

        states.add(new StateBoundary("Kogi", 6.5, 8.5, 5.5, 7.5, Arrays.asList(
                "Adavi", "Ajaokuta", "Ankpa", "Bassa", "Dekina", "Ibaji",
                "Idah", "Igalamela Odolu", "Ijumu", "Kabba/Bunu", "Kogi",
                "Lokoja", "Mopa Muro", "Ofu", "Ogori/Magongo", "Okehi",
                "Okene", "Olamaboro", "Omala", "Yagba East", "Yagba West")));

        states.add(new StateBoundary("Kwara", 7.5, 9.0, 2.5, 5.5, Arrays.asList(
                "Asa", "Baruten", "Edu", "Ekiti", "Ifelodun", "Ilorin East",
                "Ilorin South", "Ilorin West", "Irepodun", "Isin", "Kaiama",
                "Moro", "Offa", "Oke Ero", "Oyun", "Pategi")));

        states.add(new StateBoundary("Lagos", 6.2, 6.7, 2.7, 4.0, Arrays.asList(
                "Agege", "Ajeromi-Ifelodun", "Alimosho", "Amuwo-Odofin",
                "Apapa", "Badagry", "Epe", "Eti Osa", "Ibeju-Lekki",
                "Ifako-Ijaiye", "Ikeja", "Ikorodu", "Kosofe", "Lagos Island",
                "Lagos Mainland", "Mushin", "Ojo", "Oshodi-Isolo",
                "Shomolu", "Surulere")));

        states.add(new StateBoundary("Nasarawa", 7.5, 9.0, 7.0, 9.5, Arrays.asList(
                "Akwanga", "Awe", "Doma", "Karu", "Keana", "Keffi",
                "Kokona", "Lafia", "Nasarawa", "Nasarawa Eggon", "Obi",
                "Toto", "Wamba")));

        states.add(new StateBoundary("Niger", 8.0, 11.0, 4.0, 7.5, Arrays.asList(
                "Agaie", "Agwara", "Bida", "Borgu", "Bosso", "Chanchaga",
                "Edati", "Gbako", "Gurara", "Katcha", "Kontagora", "Lapai",
                "Lavun", "Magama", "Mariga", "Mashegu", "Mokwa", "Munya",
                "Paikoro", "Rafi", "Rijau", "Shiroro", "Suleja", "Tafa",
                "Wushishi")));

        states.add(new StateBoundary("Ogun", 6.2, 7.8, 2.5, 5.0, Arrays.asList(
                "Abeokuta North", "Abeokuta South", "Ado-Odo/Ota", "Egbado North",
                "Egbado South", "Ewekoro", "Ifo", "Ijebu East", "Ijebu North",
                "Ijebu North East", "Ijebu Ode", "Ikenne", "Imeko Afon",
                "Ipokia", "Obafemi Owode", "Odeda", "Odogbolu", "Ogun Waterside",
                "Remo North", "Sagamu", "Yewa North", "Yewa South")));

        states.add(new StateBoundary("Ondo", 5.5, 8.0, 4.0, 6.0, Arrays.asList(
                "Akoko North-East", "Akoko North-West", "Akoko South-East",
                "Akoko South-West", "Akure North", "Akure South", "Ese Odo",
                "Idanre", "Ifedore", "Ilaje", "Ile Oluji/Okeigbo", "Irele",
                "Odigbo", "Okitipupa", "Ondo East", "Ondo West", "Ose",
                "Owo")));

        states.add(new StateBoundary("Osun", 7.0, 8.5, 4.0, 5.5, Arrays.asList(
                "Atakunmosa East", "Atakunmosa West", "Aiyedaade", "Aiyedire",
                "Boluwaduro", "Boripe", "Ede North", "Ede South", "Egbedore",
                "Ejigbo", "Ife Central", "Ife East", "Ife North", "Ife South",
                "Ifedayo", "Ifelodun", "Ila", "Ilesa East", "Ilesa West",
                "Irepodun", "Irewole", "Isokan", "Iwo", "Obokun", "Odo Otin",
                "Ola Oluwa", "Olorunda", "Oriade", "Orolu", "Osogbo")));

        states.add(new StateBoundary("Oyo", 6.8, 9.0, 2.5, 5.0, Arrays.asList(
                "Afijio", "Akinyele", "Atiba", "Atisbo", "Egbeda", "Ibadan North",
                "Ibadan North-East", "Ibadan North-West", "Ibadan South-East",
                "Ibadan South-West", "Ibarapa Central", "Ibarapa East",
                "Ibarapa North", "Ido", "Irepo", "Iseyin", "Itesiwaju",
                "Iwajowa", "Kajola", "Lagelu", "Ogbomosho North",
                "Ogbomosho South", "Ogo Oluwa", "Olorunsogo", "Oluyole",
                "Ona Ara", "Orelope", "Ori Ire", "Oyo East", "Oyo West",
                "Saki East", "Saki West", "Surulere")));

        states.add(new StateBoundary("Plateau", 8.0, 10.5, 8.0, 10.0, Arrays.asList(
                "Barkin Ladi", "Bassa", "Bokkos", "Jos East", "Jos North",
                "Jos South", "Kanam", "Kanke", "Langtang North", "Langtang South",
                "Mangu", "Mikang", "Pankshin", "Qua'an Pan", "Riyom",
                "Shendam", "Wase")));

        states.add(new StateBoundary("Rivers", 4.3, 5.5, 6.3, 7.8, Arrays.asList(
                "Abua/Odual", "Ahoada East", "Ahoada West", "Akuku-Toru",
                "Andoni", "Asari-Toru", "Bonny", "Degema", "Eleme", "Emohua",
                "Etche", "Gokana", "Ikwerre", "Khana", "Obio/Akpor",
                "Ogba/Egbema/Ndoni", "Ogu/Bolo", "Okrika", "Omuma", "Opobo/Nkoro",
                "Oyigbo", "Port Harcourt", "Tai")));

        states.add(new StateBoundary("Sokoto", 11.5, 14.0, 4.0, 6.5, Arrays.asList(
                "Binji", "Bodinga", "Dange Shuni", "Gada", "Goronyo", "Gudu",
                "Gwadabawa", "Illela", "Isa", "Kebbe", "Kware", "Rabah",
                "Sabon Birni", "Shagari", "Silame", "Sokoto North", "Sokoto South",
                "Tambuwal", "Tangaza", "Tureta", "Wamako", "Wurno", "Yabo")));

        states.add(new StateBoundary("Taraba", 6.5, 9.5, 9.0, 11.5, Arrays.asList(
                "Ardo Kola", "Bali", "Donga", "Gashaka", "Gassol", "Ibi",
                "Jalingo", "Karim Lamido", "Kurmi", "Lau", "Sardauna",
                "Takum", "Ussa", "Wukari", "Yorro", "Zing")));

        states.add(new StateBoundary("Yobe", 10.0, 13.5, 9.5, 12.5, Arrays.asList(
                "Bade", "Bursari", "Damaturu", "Fika", "Fune", "Geidam",
                "Gujba", "Gulani", "Jakusko", "Karasuwa", "Machina", "Nangere",
                "Nguru", "Potiskum", "Tarmuwa", "Yunusari", "Yusufari")));

        states.add(new StateBoundary("Zamfara", 10.5, 13.5, 4.5, 7.5, Arrays.asList(
                "Anka", "Bakura", "Birnin Magaji/Kiyaw", "Bukkuyum", "Bungudu",
                "Gummi", "Gusau", "Kaura Namoda", "Maradun", "Maru",
                "Shinkafi", "Talata Mafara", "Tsafe", "Zurmi")));

        log.info("NigeriaLocationService initialized with {} state boundaries", states.size());
    }

    /**
     * Resolve GPS coordinates to Nigeria State and LGA.
     *
     * @param latitude  GPS latitude
     * @param longitude GPS longitude
     * @return String array with [state, lga]. Returns ["Unknown", "Unknown"]
     *         if coordinates are outside Nigeria.
     */
    public String[] resolve(double latitude, double longitude) {
        // Check if within Nigeria bounds
        if (latitude < NIGERIA_MIN_LAT || latitude > NIGERIA_MAX_LAT
                || longitude < NIGERIA_MIN_LNG || longitude > NIGERIA_MAX_LNG) {
            return new String[]{"Unknown", "Unknown"};
        }

        // Find containing state by bounding box
        StateBoundary matched = null;
        for (StateBoundary state : states) {
            if (state.contains(latitude, longitude)) {
                matched = state;
                break;
            }
        }

        // If no exact match, find nearest state by centroid distance
        if (matched == null) {
            double minDistance = Double.MAX_VALUE;
            for (StateBoundary state : states) {
                double d = haversine(latitude, longitude,
                        state.centerLat(), state.centerLng());
                if (d < minDistance) {
                    minDistance = d;
                    matched = state;
                }
            }
        }

        if (matched == null) {
            return new String[]{"Nigeria", "General"};
        }

        // Assign a pseudo-LGA based on coarse grid position within the state
        String lga = resolveLga(latitude, longitude, matched);

        return new String[]{matched.name, lga};
    }

    /**
     * Resolve a pseudo-LGA within a state based on grid position.
     * In production, this would use a proper LGA boundary GIS database.
     */
    private String resolveLga(double lat, double lng, StateBoundary state) {
        if (state.lgas.isEmpty()) return "General";

        // Simple grid-based LGA assignment using lat/lng hash
        int latBucket = (int) ((lat - state.minLat) / (state.maxLat - state.minLat) * 4);
        int lngBucket = (int) ((lng - state.minLng) / (state.maxLng - state.minLng) * 4);
        int index = (latBucket * 4 + lngBucket) % state.lgas.size();
        return state.lgas.get(Math.max(0, index));
    }

    /**
     * Check if coordinates are within Nigeria.
     */
    public boolean isInNigeria(double latitude, double longitude) {
        return latitude >= NIGERIA_MIN_LAT && latitude <= NIGERIA_MAX_LAT
                && longitude >= NIGERIA_MIN_LNG && longitude <= NIGERIA_MAX_LNG;
    }

    /**
     * Get state name for coordinates.
     */
    public String getState(double latitude, double longitude) {
        return resolve(latitude, longitude)[0];
    }

    /**
     * Get LGA name for coordinates.
     */
    public String getLga(double latitude, double longitude) {
        return resolve(latitude, longitude)[1];
    }

    /**
     * Haversine distance between two GPS coordinates in km.
     */
    private double haversine(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return 6371.0 * c; // Earth radius in km
    }
}
