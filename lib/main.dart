import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
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
  bool _isScanning = false;
  String _statusMessage = 'NFC Card স্ক্যান করতে বাটনে চাপো';
  List<String> _nfcDataList = [];

  Future<void> _startNfcScan() async {
    bool isAvailable = await NfcManager.instance.isAvailable();

    if (!isAvailable) {
      setState(() {
        _statusMessage = '❌ এই ডিভাইসে NFC সাপোর্ট নেই বা বন্ধ আছে';
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _statusMessage = '📡 Card কাছে ধরো...';
      _nfcDataList = [];
    });

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        try {
          List<String> extractedData = _extractTagData(tag);
          setState(() {
            _nfcDataList = extractedData;
            _statusMessage = '✅ Card পড়া সফল হয়েছে!';
            _isScanning = false;
          });
        } catch (e) {
          setState(() {
            _statusMessage = '❌ Error: ${e.toString()}';
            _isScanning = false;
          });
        }
        await NfcManager.instance.stopSession();
      },
      pollingOptions: {},
    );
  }

  List<String> _extractTagData(NfcTag tag) {
    List<String> dataList = [];
    final tagData = tag.data;

    // ── Tag type keys দেখাও ──

    // ── UID বের করো (সব ধরনের card এর জন্য) ──
    final rawId =
        tagData['nfca']?['identifier'] ??
        tagData['nfcb']?['identifier'] ??
        tagData['nfcf']?['identifier'] ??
        tagData['nfcv']?['identifier'] ??
        tagData['isodep']?['identifier'] ??
        tagData['mifareclassic']?['identifier'] ??
        tagData['mifareultralight']?['identifier'];

    if (rawId != null) {
      final uid = (rawId as List<dynamic>)
          .map(
            (e) => (e as int).toRadixString(16).padLeft(2, '0').toUpperCase(),
          )
          .join(':');
      dataList.insert(1, '🪪 UID: $uid');
    }

    // ── NDEF data ──
    // nfc_manager 3.x এ NdefMessage সরাসরি tagData থেকে পড়তে হয়
    final ndefRaw = tagData['ndef'];
    if (ndefRaw != null) {
      dataList.add('📄 NDEF সাপোর্টেড: হ্যাঁ');

      final cachedMessage = ndefRaw['cachedMessage'];
      if (cachedMessage != null) {
        final records = cachedMessage['records'] as List<dynamic>? ?? [];

        if (records.isEmpty) {
          dataList.add('📭 Card খালি (কোনো NDEF record নেই)');
        }

        for (int i = 0; i < records.length; i++) {
          final record = records[i] as Map<String, dynamic>;
          dataList.add('--- Record ${i + 1} ---');

          final typeNameFormat = record['typeNameFormat'] as int? ?? 0;
          final typeBytes = record['type'] as List<dynamic>? ?? [];
          final payloadBytes = record['payload'] as List<dynamic>? ?? [];

          final recordType = String.fromCharCodes(typeBytes.cast<int>());
          dataList.add('📌 Type: $recordType');

          // TNF 0x01 = NFC Well Known
          if (typeNameFormat == 0x01) {
            if (recordType == 'T') {
              // ── Text record ──
              final payload = payloadBytes.cast<int>();
              if (payload.isNotEmpty) {
                final langLen = payload[0] & 0x3F;
                final text = String.fromCharCodes(payload.sublist(1 + langLen));
                dataList.add('📝 Text: $text');
              }
            } else if (recordType == 'U') {
              // ── URI record ──
              const uriPrefixes = [
                '',
                'http://www.',
                'https://www.',
                'http://',
                'https://',
                'tel:',
                'mailto:',
                'ftp://anonymous:anonymous@',
                'ftp://ftp.',
                'ftps://',
                'sftp://',
                'smb://',
                'nfs://',
                'ftp://',
                'dav://',
                'news:',
                'telnet://',
                'imap:',
                'rtsp://',
                'urn:',
                'pop:',
                'sip:',
                'sips:',
                'tftp:',
                'btspp://',
                'btl2cap://',
                'btgoep://',
                'tcpobex://',
                'irdaobex://',
                'file://',
              ];
              final payload = payloadBytes.cast<int>();
              if (payload.isNotEmpty) {
                final prefixIndex = payload[0];
                final prefix = prefixIndex < uriPrefixes.length
                    ? uriPrefixes[prefixIndex]
                    : '';
                final uri = prefix + String.fromCharCodes(payload.sublist(1));
                dataList.add('🔗 URI: $uri');
              }
            } else {
              // অন্য Well Known record
              final payloadStr = String.fromCharCodes(payloadBytes.cast<int>());
              dataList.add('📦 Data: $payloadStr');
            }
          } else if (typeNameFormat == 0x02) {
            // TNF 0x02 = MIME type
            final payloadStr = String.fromCharCodes(payloadBytes.cast<int>());
            dataList.add('📧 MIME Data: $payloadStr');
          } else {
            // অন্য যেকোনো TNF
            final hex = payloadBytes
                .cast<int>()
                .map((e) => e.toRadixString(16).padLeft(2, '0'))
                .join(' ');
            dataList.add('🔣 HEX: $hex');
          }
        }
      } else {
        dataList.add('📭 Card খালি (NDEF message নেই)');
      }
    }

    // ── NFC-A raw info ──
    final nfcA = tagData['nfca'];
    if (nfcA != null) {
      dataList.add('--- NFC-A Info ---');
      dataList.add('🔢 ATQA: ${nfcA['atqa']}');
      dataList.add('🔢 SAK: ${nfcA['sak']}');
    }

    // ── NFC-B raw info ──
    final nfcB = tagData['nfcb'];
    if (nfcB != null) {
      dataList.add('--- NFC-B Info ---');
      dataList.add('📡 App Data: ${nfcB['applicationData']}');
    }

    // ── ISO-DEP (smart card) ──
    final isoDep = tagData['isodep'];
    if (isoDep != null) {
      dataList.add('--- ISO-DEP Info ---');
      dataList.add('💳 HI Layer: ${isoDep['hiLayerResponse']}');
      dataList.add('💳 Historical: ${isoDep['historicalBytes']}');
    }

    // ── Mifare Classic ──
    final mifare = tagData['mifareclassic'];
    if (mifare != null) {
      dataList.add('--- MIFARE Classic ---');
      dataList.add('🃏 Type: ${mifare['type']}');
      dataList.add('🃏 Size: ${mifare['size']} bytes');
      dataList.add('🃏 Sectors: ${mifare['sectorCount']}');
      dataList.add('🃏 Blocks: ${mifare['blockCount']}');
    }

    // ── Mifare Ultralight ──
    final ultralight = tagData['mifareultralight'];
    if (ultralight != null) {
      dataList.add('--- MIFARE Ultralight ---');
      dataList.add('⚡ Type: ${ultralight['type']}');
    }

    return dataList;
  }

  Future<void> _stopScan() async {
    await NfcManager.instance.stopSession();
    setState(() {
      _isScanning = false;
      _statusMessage = 'স্ক্যান বাতিল করা হয়েছে';
    });
  }

  @override
  void dispose() {
    if (_isScanning) NfcManager.instance.stopSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A2733),
        title: const Text(
          'NFC Card Reader',
          style: TextStyle(
            color: Colors.tealAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2733),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isScanning ? Colors.tealAccent : Colors.grey.shade700,
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isScanning
                          ? Colors.tealAccent.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.1),
                    ),
                    child: Icon(
                      Icons.nfc_rounded,
                      size: 45,
                      color: _isScanning ? Colors.tealAccent : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isScanning ? Colors.tealAccent : Colors.white70,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? _stopScan : _startNfcScan,
                icon: Icon(
                  _isScanning ? Icons.stop_circle : Icons.wifi_tethering,
                ),
                label: Text(
                  _isScanning ? 'স্ক্যান বন্ধ করো' : 'NFC স্ক্যান শুরু করো',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isScanning
                      ? Colors.redAccent
                      : Colors.tealAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_nfcDataList.isNotEmpty) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Card Data:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2733),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _nfcDataList.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white12, height: 12),
                    itemBuilder: (context, index) {
                      final item = _nfcDataList[index];
                      final isHeader = item.startsWith('---');
                      return Text(
                        item,
                        style: TextStyle(
                          color: isHeader ? Colors.tealAccent : Colors.white70,
                          fontSize: isHeader ? 13 : 14,
                          fontWeight: isHeader
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontFamily: 'monospace',
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

extension on Object {
  operator [](String other) {}
}
