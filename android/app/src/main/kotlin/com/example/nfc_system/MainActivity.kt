package com.example.nfc_system  // তোমার package name

import android.app.PendingIntent
import android.content.Intent
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.*
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var nfcAdapter: NfcAdapter? = null
    private var pendingIntent: PendingIntent? = null
    private val CHANNEL = "nfc_channel"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        nfcAdapter = NfcAdapter.getDefaultAdapter(this)

        val intent = Intent(this, javaClass).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }

        pendingIntent = PendingIntent.getActivity(this, 0, intent, flags)
    }

    override fun onResume() {
        super.onResume()
        nfcAdapter?.enableForegroundDispatch(this, pendingIntent, null, null)
    }

    override fun onPause() {
        super.onPause()
        nfcAdapter?.disableForegroundDispatch(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d("NFC", "onNewIntent: ${intent.action}")

        val action = intent.action
        if (action != NfcAdapter.ACTION_TAG_DISCOVERED &&
            action != NfcAdapter.ACTION_NDEF_DISCOVERED &&
            action != NfcAdapter.ACTION_TECH_DISCOVERED) return

        val tag: Tag? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(NfcAdapter.EXTRA_TAG, Tag::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(NfcAdapter.EXTRA_TAG)
        }

        tag?.let { processTag(it) }
    }

    private fun processTag(tag: Tag) {
        val result = mutableMapOf<String, Any>()

        // ── UID ──
        val uid = tag.id.joinToString(":") {
            it.toInt().and(0xFF).toString(16).padStart(2, '0').uppercase()
        }
        val uidDecimal = tag.id.fold(0L) { acc, byte ->
            (acc shl 8) or (byte.toLong() and 0xFF)
        }
        result["uid"] = uid
        result["uid_decimal"] = uidDecimal.toString()
        result["uid_bytes"] = tag.id.size.toString()

        // ── Tech List ──
        val techList = tag.techList.map { it.split(".").last() }
        result["tech_list"] = techList

        // ── Card Type detect ──
        result["card_type"] = detectCardType(tag)

        // ── NDEF data ──
        val ndefData = mutableListOf<String>()
        try {
            val ndef = Ndef.get(tag)
            if (ndef != null) {
                ndef.connect()
                result["ndef_writable"] = ndef.isWritable.toString()
                result["ndef_max_size"] = "${ndef.maxSize} bytes"
                result["ndef_type"] = ndef.type ?: "Unknown"

                val message = ndef.ndefMessage ?: ndef.cachedNdefMessage
                if (message != null) {
                    for ((index, record) in message.records.withIndex()) {
                        val tnf = record.tnf
                        val type = String(record.type)
                        val payload = record.payload

                        when {
                            // Text record
                            tnf == android.nfc.NdefRecord.TNF_WELL_KNOWN &&
                                    type == "T" -> {
                                val langLen = payload[0].toInt() and 0x3F
                                val text = String(payload.copyOfRange(1 + langLen, payload.size))
                                ndefData.add("Record ${index + 1}: [TEXT] $text")
                            }
                            // URI record
                            tnf == android.nfc.NdefRecord.TNF_WELL_KNOWN &&
                                    type == "U" -> {
                                val prefixes = arrayOf(
                                    "", "http://www.", "https://www.",
                                    "http://", "https://", "tel:", "mailto:"
                                )
                                val prefixIdx = payload[0].toInt() and 0xFF
                                val prefix = if (prefixIdx < prefixes.size) prefixes[prefixIdx] else ""
                                val uri = prefix + String(payload.copyOfRange(1, payload.size))
                                ndefData.add("Record ${index + 1}: [URI] $uri")
                            }
                            // MIME type
                            tnf == android.nfc.NdefRecord.TNF_MIME_MEDIA -> {
                                val text = String(payload)
                                ndefData.add("Record ${index + 1}: [MIME:$type] $text")
                            }
                            else -> {
                                val hex = payload.joinToString(" ") {
                                    it.toInt().and(0xFF).toString(16).padStart(2, '0').uppercase()
                                }
                                ndefData.add("Record ${index + 1}: [TNF:$tnf] HEX: $hex")
                            }
                        }
                    }
                } else {
                    ndefData.add("NDEF card কিন্তু data নেই (খালি)")
                }
                ndef.close()
            }
        } catch (e: Exception) {
            Log.e("NFC", "NDEF error: ${e.message}")
            ndefData.add("NDEF read error: ${e.message}")
        }
        result["ndef_records"] = ndefData

        // ── MIFARE Classic info ──
        try {
            val mifare = MifareClassic.get(tag)
            if (mifare != null) {
                result["mifare_type"] = when (mifare.type) {
                    MifareClassic.TYPE_CLASSIC -> "MIFARE Classic"
                    MifareClassic.TYPE_PLUS -> "MIFARE Plus"
                    MifareClassic.TYPE_PRO -> "MIFARE Pro"
                    else -> "MIFARE Unknown"
                }
                result["mifare_size"] = "${mifare.size} bytes"
                result["mifare_sectors"] = mifare.sectorCount.toString()
                result["mifare_blocks"] = mifare.blockCount.toString()
            }
        } catch (e: Exception) {
            Log.e("NFC", "MIFARE error: ${e.message}")
        }

        // ── MIFARE Ultralight ──
        try {
            val ultra = MifareUltralight.get(tag)
            if (ultra != null) {
                result["ultralight_type"] = when (ultra.type) {
                    MifareUltralight.TYPE_ULTRALIGHT -> "MIFARE Ultralight"
                    MifareUltralight.TYPE_ULTRALIGHT_C -> "MIFARE Ultralight C"
                    else -> "Ultralight Unknown"
                }
            }
        } catch (e: Exception) {
            Log.e("NFC", "Ultralight error: ${e.message}")
        }

        // ── IsoDep (Smart Card) ──
        try {
            val isoDep = IsoDep.get(tag)
            if (isoDep != null) {
                isoDep.connect()
                result["isodep_max_transceive"] = "${isoDep.maxTransceiveLength} bytes"
                val historical = isoDep.historicalBytes
                if (historical != null) {
                    result["isodep_historical"] = historical.joinToString(" ") {
                        it.toInt().and(0xFF).toString(16).padStart(2, '0').uppercase()
                    }
                }
                isoDep.close()
            }
        } catch (e: Exception) {
            Log.e("NFC", "IsoDep error: ${e.message}")
        }

        // ── NfcA info ──
        try {
            val nfcA = NfcA.get(tag)
            if (nfcA != null) {
                result["nfca_atqa"] = nfcA.atqa.joinToString(" ") {
                    it.toInt().and(0xFF).toString(16).padStart(2, '0').uppercase()
                }
                result["nfca_sak"] = nfcA.sak.toString()
                result["nfca_max_transceive"] = "${nfcA.maxTransceiveLength} bytes"
            }
        } catch (e: Exception) {
            Log.e("NFC", "NfcA error: ${e.message}")
        }

        // ── NfcB info ──
        try {
            val nfcB = NfcB.get(tag)
            if (nfcB != null) {
                result["nfcb_app_data"] = nfcB.applicationData.joinToString(" ") {
                    it.toInt().and(0xFF).toString(16).padStart(2, '0').uppercase()
                }
                result["nfcb_protocol_info"] = nfcB.protocolInfo.joinToString(" ") {
                    it.toInt().and(0xFF).toString(16).padStart(2, '0').uppercase()
                }
            }
        } catch (e: Exception) {
            Log.e("NFC", "NfcB error: ${e.message}")
        }

        Log.d("NFC", "Result: $result")

        runOnUiThread {
            methodChannel?.invokeMethod("onNfcTag", result)
        }
    }

    private fun detectCardType(tag: Tag): String {
        val techs = tag.techList.map { it.split(".").last() }
        return when {
            techs.contains("MifareClassic") -> "MIFARE Classic"
            techs.contains("MifareUltralight") -> "MIFARE Ultralight"
            techs.contains("IsoDep") && techs.contains("NfcA") -> "ISO 14443-4A (Smart Card)"
            techs.contains("IsoDep") && techs.contains("NfcB") -> "ISO 14443-4B (Smart Card)"
            techs.contains("NfcF") -> "NFC-F (FeliCa)"
            techs.contains("NfcV") -> "NFC-V (ISO 15693)"
            techs.contains("Ndef") -> "NDEF Tag"
            techs.contains("NfcA") -> "NFC-A (ISO 14443-3A)"
            techs.contains("NfcB") -> "NFC-B (ISO 14443-3B)"
            else -> "Unknown (${techs.joinToString()})"
        }
    }
}