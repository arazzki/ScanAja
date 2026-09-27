package com.example.scanaja

import android.app.Activity
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.example.scanaja/scanner"
    private val TAG = "ScanAja"
    private var pendingResult: MethodChannel.Result? = null

    private lateinit var scannerLauncher: ActivityResultLauncher<IntentSenderRequest>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        scannerLauncher = registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
            if (result.resultCode == Activity.RESULT_OK) {
                try {
                    val scanResult = GmsDocumentScanningResult.fromActivityResultIntent(result.data)
                    scanResult?.pages?.let { pages ->
                        val paths = pages.map { page -> copyUriToCache(page.imageUri) }
                        pendingResult?.success(paths)
                    } ?: run {
                        pendingResult?.error("SCAN_EMPTY", "Tidak ada halaman yang didapat", null)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error processing scan result", e)
                    pendingResult?.error("COPY_FAILED", "Gagal memproses gambar: ${e.message}", null)
                }
            } else if (result.resultCode == Activity.RESULT_CANCELED) {
                pendingResult?.success(null)
            } else {
                pendingResult?.error("SCAN_ERROR", "Scanning gagal dengan kode: ${result.resultCode}", null)
            }
            pendingResult = null
        }
    }

    private fun copyUriToCache(uri: Uri): String {
        val destinationFile = File(cacheDir, "scan_${System.currentTimeMillis()}_${(1..1000).random()}.jpg")
        contentResolver.openInputStream(uri)?.use { inputStream ->
            FileOutputStream(destinationFile).use { outputStream ->
                inputStream.copyTo(outputStream)
            }
        }
        return destinationFile.absolutePath
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startScan") {
                pendingResult = result
                ensureModuleThenScan()
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getScanner(): com.google.mlkit.vision.documentscanner.GmsDocumentScanner {
        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(true)
            .setPageLimit(10)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .build()
        return GmsDocumentScanning.getClient(options)
    }

    private fun ensureModuleThenScan() {
        try {
            val scanner = getScanner()
            val moduleInstallClient = ModuleInstall.getClient(this)

            // Cek apakah modul scanner sudah tersedia
            moduleInstallClient.areModulesAvailable(scanner)
                .addOnSuccessListener { response ->
                    if (response.areModulesAvailable()) {
                        // Modul sudah tersedia, langsung scan
                        Log.d(TAG, "Scanner module sudah tersedia, membuka scanner...")
                        launchScanner(scanner)
                    } else {
                        // Modul belum tersedia, minta install dulu
                        Log.d(TAG, "Scanner module belum tersedia, mengunduh...")
                        installModuleThenScan(scanner)
                    }
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "Gagal cek modul", e)
                    // Coba langsung scan saja
                    launchScanner(scanner)
                }
        } catch (e: Exception) {
            Log.e(TAG, "Exception saat inisialisasi scanner", e)
            pendingResult?.error("INIT_ERROR", "Gagal inisialisasi: ${e::class.java.simpleName} - ${e.message ?: "unknown"}", null)
            pendingResult = null
        }
    }

    private fun installModuleThenScan(scanner: com.google.mlkit.vision.documentscanner.GmsDocumentScanner) {
        val moduleInstallClient = ModuleInstall.getClient(this)
        val installRequest = ModuleInstallRequest.newBuilder()
            .addApi(scanner)
            .build()

        moduleInstallClient.installModules(installRequest)
            .addOnSuccessListener {
                Log.d(TAG, "Modul scanner berhasil diinstall, membuka scanner...")
                launchScanner(scanner)
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Gagal install modul scanner", e)
                pendingResult?.error("MODULE_INSTALL_FAILED",
                    "Gagal mengunduh modul scanner. Pastikan Google Play Services di HP Anda sudah diperbarui. Error: ${e.message}",
                    null)
                pendingResult = null
            }
    }

    private fun launchScanner(scanner: com.google.mlkit.vision.documentscanner.GmsDocumentScanner) {
        scanner.getStartScanIntent(this)
            .addOnSuccessListener { intentSender ->
                try {
                    scannerLauncher.launch(IntentSenderRequest.Builder(intentSender).build())
                } catch (e: Exception) {
                    Log.e(TAG, "Gagal meluncurkan scanner intent", e)
                    pendingResult?.error("LAUNCH_FAILED", "Gagal membuka scanner: ${e.message}", null)
                    pendingResult = null
                }
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "getStartScanIntent gagal", e)
                pendingResult?.error("SCAN_START_FAILED",
                    "Gagal membuka scanner: ${e::class.java.simpleName} - ${e.message ?: "unknown"}. Coba perbarui Google Play Services.",
                    null)
                pendingResult = null
            }
    }
}
