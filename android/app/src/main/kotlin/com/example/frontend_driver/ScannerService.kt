package com.example.frontend_driver

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

class ScannerService : LifecycleService() {

    private val executor = Executors.newSingleThreadExecutor()
    private val barcodeScanner = BarcodeScanning.getClient()
    private var isProcessing = false
    private var lastScannedTime = 0L

    private var token: String? = null
    private var baseUrl: String? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        if (intent?.action == "STOP") {
            Log.i("ScannerService", "Stopping service")
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        }

        token = intent?.getStringExtra("TOKEN")
        baseUrl = intent?.getStringExtra("BASE_URL")
        
        Log.i("ScannerService", "Service started, Base URL: $baseUrl")

        createNotificationChannel()
        val notification = NotificationCompat.Builder(this, "scanner_channel")
            .setContentTitle("Paraqar Scanner")
            .setContentText("Scanning for QR codes in background...")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .build()
        
        startForeground(1, notification)
        startCamera()

        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "scanner_channel",
                "Scanner Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()
            
            // Image analysis for ML Kit
            val imageAnalysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()

            imageAnalysis.setAnalyzer(executor) { imageProxy ->
                processImageProxy(imageProxy)
            }

            // Dummy preview to force the camera pipeline to start streaming frames
            val preview = Preview.Builder().build()
            preview.setSurfaceProvider { request ->
                val surfaceTexture = SurfaceTexture(10)
                surfaceTexture.setDefaultBufferSize(request.resolution.width, request.resolution.height)
                val surface = Surface(surfaceTexture)
                request.provideSurface(surface, ContextCompat.getMainExecutor(this@ScannerService)) {
                    surface.release()
                    surfaceTexture.release()
                }
            }

            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            try {
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(
                    this, cameraSelector, preview, imageAnalysis
                )
                Log.i("ScannerService", "Camera bound successfully to lifecycle")
            } catch (exc: Exception) {
                Log.e("ScannerService", "Use case binding failed", exc)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    @SuppressLint("UnsafeOptInUsageError")
    private fun processImageProxy(imageProxy: ImageProxy) {
        if (isProcessing) {
            imageProxy.close()
            return
        }

        val now = System.currentTimeMillis()
        if (now - lastScannedTime < 2500) {
            imageProxy.close()
            return
        }

        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            barcodeScanner.process(image)
                .addOnSuccessListener { barcodes ->
                    if (barcodes.isNotEmpty()) {
                        val rawValue = barcodes.first().rawValue
                        if (rawValue != null) {
                            Log.i("ScannerService", "Barcode detected: $rawValue")
                            isProcessing = true
                            lastScannedTime = System.currentTimeMillis()
                            validateQrCode(rawValue)
                        }
                    }
                }
                .addOnFailureListener { e ->
                    Log.e("ScannerService", "Barcode scanning failed", e)
                }
                .addOnCompleteListener {
                    imageProxy.close()
                }
        } else {
            imageProxy.close()
        }
    }

    private fun validateQrCode(qrToken: String) {
        if (baseUrl == null || token == null) {
            Log.e("ScannerService", "Missing base URL or token")
            isProcessing = false
            return
        }
        executor.execute {
            try {
                Log.i("ScannerService", "Validating QR token via API...")
                val url = URL("$baseUrl/qr/validate")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("Authorization", "Bearer $token")
                conn.doOutput = true

                val jsonInputString = "{\"token\": \"$qrToken\"}"
                OutputStreamWriter(conn.outputStream).use { os ->
                    os.write(jsonInputString)
                }

                val responseCode = conn.responseCode
                Log.i("ScannerService", "API Response Code: $responseCode")
                if (responseCode == 200) {
                    playSound(true)
                } else {
                    playSound(false)
                }
            } catch (e: Exception) {
                Log.e("ScannerService", "API Error", e)
                playSound(false)
            } finally {
                Thread.sleep(2500)
                isProcessing = false
            }
        }
    }

    private fun playSound(success: Boolean) {
        Handler(Looper.getMainLooper()).post {
            try {
                val resId = if (success) R.raw.success else R.raw.error
                val player = MediaPlayer.create(this@ScannerService, resId)
                player?.setOnCompletionListener { it.release() }
                player?.start()
                Log.i("ScannerService", "Playing sound: success=$success")
            } catch (e: Exception) {
                Log.e("ScannerService", "Audio Error", e)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        executor.shutdown()
        Log.i("ScannerService", "Service destroyed")
    }
}
