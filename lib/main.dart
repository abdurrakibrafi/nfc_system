import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NFC Reader',
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.dark,
      home: const NfcReaderPage(),
    );
  }
}

class NfcReaderPage extends StatefulWidget {
  const NfcReaderPage({super.key});

  @override
  State<NfcReaderPage> createState() => _NfcReaderPageState();
}

class _NfcReaderPageState extends State<NfcReaderPage> {
  static const _channel = MethodChannel('nfc_channel');

  bool _hasData = false;
  Map<String, dynamic> _cardData = {};

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNfcTag') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        setState(() {
          _cardData = args;
          _hasData = true;
        });
      }
    });
  }

  String _get(String key, [String fallback = 'N/A']) =>
      _cardData[key]?.toString() ?? fallback;

  List<String> _getList(String key) {
    final val = _cardData[key];
    if (val is List) return val.map((e) => e.toString()).toList();
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        elevation: 0,
        title: const Text(
          '📶 NFC Card Reader',
          style: TextStyle(
            color: Colors.tealAccent,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_hasData)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.tealAccent),
              onPressed: () => setState(() {
                _hasData = false;
                _cardData = {};
              }),
            ),
        ],
      ),
      body: _hasData ? _buildDataView() : _buildWaitingView(),
    );
  }

  // ── Waiting Screen ──
  Widget _buildWaitingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.tealAccent.withOpacity(0.1),
              border: Border.all(color: Colors.tealAccent, width: 2),
            ),
            child: const Icon(
              Icons.nfc_rounded,
              size: 70,
              color: Colors.tealAccent,
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            'NFC Card কাছে ধরো',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Phone এর পিছনে camera এর কাছে ধরো',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Data View ──
  Widget _buildDataView() {
    final techList = _getList('tech_list');
    final ndefRecords = _getList('ndef_records');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Card Identity ──
          _sectionCard(
            title: '🪪 Card Identity',
            color: Colors.tealAccent,
            children: [
              _row('Card Type', _get('card_type')),
              _row('UID (HEX)', _get('uid')),
              _row('UID (Decimal)', _get('uid_decimal')),
              _row('UID Length', '${_get('uid_bytes')} bytes'),
            ],
          ),

          const SizedBox(height: 12),

          // ── Technology ──
          _sectionCard(
            title: '📡 Technology',
            color: Colors.blueAccent,
            children: [
              if (techList.isNotEmpty)
                ...techList.map((t) => _row('Tech', t))
              else
                _row('Tech', 'N/A'),
            ],
          ),

          const SizedBox(height: 12),

          // ── NFC-A Info ──
          if (_cardData.containsKey('nfca_sak')) ...[
            _sectionCard(
              title: '🔷 NFC-A Info',
              color: Colors.purpleAccent,
              children: [
                _row('ATQA', _get('nfca_atqa')),
                _row('SAK', _get('nfca_sak')),
                _row('Max Transceive', _get('nfca_max_transceive')),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ── NFC-B Info ──
          if (_cardData.containsKey('nfcb_app_data')) ...[
            _sectionCard(
              title: '🔶 NFC-B Info',
              color: Colors.orangeAccent,
              children: [
                _row('App Data', _get('nfcb_app_data')),
                _row('Protocol Info', _get('nfcb_protocol_info')),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ── MIFARE Info ──
          if (_cardData.containsKey('mifare_type')) ...[
            _sectionCard(
              title: '💳 MIFARE Info',
              color: Colors.greenAccent,
              children: [
                _row('Type', _get('mifare_type')),
                _row('Size', _get('mifare_size')),
                _row('Sectors', _get('mifare_sectors')),
                _row('Blocks', _get('mifare_blocks')),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ── MIFARE Ultralight ──
          if (_cardData.containsKey('ultralight_type')) ...[
            _sectionCard(
              title: '⚡ Ultralight Info',
              color: Colors.yellowAccent,
              children: [
                _row('Type', _get('ultralight_type')),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ── ISO-DEP ──
          if (_cardData.containsKey('isodep_max_transceive')) ...[
            _sectionCard(
              title: '🔐 ISO-DEP (Smart Card)',
              color: Colors.redAccent,
              children: [
                _row('Max Transceive', _get('isodep_max_transceive')),
                _row('Historical Bytes', _get('isodep_historical')),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ── NDEF ──
          if (_cardData.containsKey('ndef_type')) ...[
            _sectionCard(
              title: '📄 NDEF Data',
              color: Colors.cyanAccent,
              children: [
                _row('NDEF Type', _get('ndef_type')),
                _row('Writable', _get('ndef_writable')),
                _row('Max Size', _get('ndef_max_size')),
                if (ndefRecords.isNotEmpty) ...[
                  const Divider(color: Colors.white12),
                  ...ndefRecords.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      r,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  )),
                ],
              ],
            ),
            const SizedBox(height: 12),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Section Card Widget ──
  Widget _sectionCard({
    required String title,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF131929),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          // Rows
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  // ── Row Widget ──
  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}