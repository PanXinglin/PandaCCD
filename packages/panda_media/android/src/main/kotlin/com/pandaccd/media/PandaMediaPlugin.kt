package com.pandaccd.media

import android.graphics.*
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceContour
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.UUID
import java.util.concurrent.Executors

/** System decoding/encoding and face coordinates. No beauty/color algorithms. */
class PandaMediaPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val faceLimit = 8 // Must match FaceRegion.maxFaces.
    private val detector by lazy { FaceDetection.getClient(FaceDetectorOptions.Builder()
        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
        .setMinFaceSize(.06f).build()) }
    private val contourDetector by lazy { FaceDetection.getClient(FaceDetectorOptions.Builder()
        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
        .setContourMode(FaceDetectorOptions.CONTOUR_MODE_ALL).setMinFaceSize(.08f).build()) }
    private val readers = mutableMapOf<String, MediaMetadataRetriever>()
    private val writers = mutableMapOf<String, MovieEncoder>()
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "panda_ccd/media")
        channel.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.execute {
            readers.values.forEach { it.release() }; readers.clear()
            writers.values.forEach { it.abort() }; writers.clear(); detector.close(); contourDetector.close()
        }
        executor.shutdown()
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            try {
                val value: Any? = when(call.method) {
                    "device" -> mapOf("brand" to Build.BRAND, "manufacturer" to Build.MANUFACTURER)
                    "detectPhoto" -> {
                        val bitmap = BitmapFactory.decodeByteArray(call.argument<ByteArray>("bytes"), 0,
                            call.argument<ByteArray>("bytes")!!.size) ?: error("Invalid image")
                        try { detectBitmap(bitmap) }
                        finally { bitmap.recycle() }
                    }
                    "detectPixels" -> {
                        val w=call.argument<Int>("width")!!;val h=call.argument<Int>("height")!!
                        val bytes=call.argument<ByteArray>("bytes")!!
                        if(call.argument<Boolean>("bgra")==true) {var i=0;while(i<bytes.size){val r=bytes[i];bytes[i]=bytes[i+2];bytes[i+2]=r;i+=4}}
                        val bitmap=Bitmap.createBitmap(w,h,Bitmap.Config.ARGB_8888)
                        try {bitmap.copyPixelsFromBuffer(java.nio.ByteBuffer.wrap(bytes));detectBitmap(bitmap)}finally{bitmap.recycle()}
                    }
                    "detectFrame" -> {
                        val w = call.argument<Int>("width")!!; val h = call.argument<Int>("height")!!
                        val rotation = call.argument<Int>("rotation")!!
                        val bytes = call.argument<ByteArray>("bytes")!!
                        val image = InputImage.fromByteArray(bytes, w, h, rotation, android.graphics.ImageFormat.NV21)
                        val boxes = detectBoxes(image)
                        if (boxes.isEmpty()) emptyList() else {
                            val encoded = ByteArrayOutputStream().use { output ->
                                check(YuvImage(bytes, ImageFormat.NV21, w, h, null)
                                    .compressToJpeg(Rect(0, 0, w, h), 90, output))
                                output.toByteArray()
                            }
                            val bitmap = BitmapFactory.decodeByteArray(encoded, 0, encoded.size)
                                ?: error("Invalid camera frame")
                            try {
                                val upright = if (rotation == 0) bitmap else Bitmap.createBitmap(
                                    bitmap, 0, 0, w, h, Matrix().apply { postRotate(rotation.toFloat()) }, true)
                                try { describeFaces(upright, boxes) }
                                finally { if (upright !== bitmap) upright.recycle() }
                            } finally { bitmap.recycle() }
                        }
                    }
                    "jpeg" -> {
                        val bytes = call.argument<ByteArray>("bytes")!!
                        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: error("Invalid image")
                        try { encode(bitmap, Bitmap.CompressFormat.JPEG) } finally { bitmap.recycle() }
                    }
                    "openReader" -> {
                        val reader = MediaMetadataRetriever()
                        try {
                            reader.setDataSource(call.argument<String>("path")!!)
                            val id = UUID.randomUUID().toString(); readers[id] = reader
                            mapOf("id" to id, "durationUs" to ((reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0L)*1000))
                        } catch(e: Exception) { reader.release(); throw e }
                    }
                    "readPixels" -> {
                        val reader=readers[call.argument<String>("id")]?:error("Reader closed")
                        val time=call.argument<Number>("timeUs")!!.toLong();val edge=call.argument<Int>("maxEdge")?:720
                        val w=reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toInt()?:edge
                        val h=reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toInt()?:edge
                        val scale=minOf(1.0,edge.toDouble()/maxOf(w,h))
                        val bitmap=if(Build.VERSION.SDK_INT>=27)reader.getScaledFrameAtTime(time,MediaMetadataRetriever.OPTION_CLOSEST,maxOf(2,(w*scale).toInt()),maxOf(2,(h*scale).toInt()))else reader.getFrameAtTime(time,MediaMetadataRetriever.OPTION_CLOSEST)
                        bitmap?:error("Video frame unavailable")
                        try {
                            val buffer=java.nio.ByteBuffer.allocate(bitmap.rowBytes*bitmap.height);bitmap.copyPixelsToBuffer(buffer)
                            var data=buffer.array()
                            if(bitmap.rowBytes!=bitmap.width*4) {val packed=ByteArray(bitmap.width*bitmap.height*4);for(row in 0 until bitmap.height)System.arraycopy(data,row*bitmap.rowBytes,packed,row*bitmap.width*4,bitmap.width*4);data=packed}
                            // Android ARGB_8888 Bitmap buffers expose RGBA bytes
                            // on the supported little-endian ABIs, unlike iOS BGRA.
                            mapOf("bytes" to data,"width" to bitmap.width,"height" to bitmap.height,"bgra" to false)
                        }finally{bitmap.recycle()}
                    }
                    "readFrame" -> {
                        val reader = readers[call.argument<String>("id")] ?: error("Reader closed")
                        val time = call.argument<Number>("timeUs")!!.toLong()
                        val edge = call.argument<Int>("maxEdge") ?: 960
                        val w = reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toInt() ?: edge
                        val h = reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toInt() ?: edge
                        val scale = minOf(1.0, edge.toDouble()/maxOf(w,h))
                        val bitmap = if(Build.VERSION.SDK_INT >= 27) reader.getScaledFrameAtTime(time,
                            MediaMetadataRetriever.OPTION_CLOSEST, maxOf(2,(w*scale).toInt()), maxOf(2,(h*scale).toInt()))
                            else reader.getFrameAtTime(time, MediaMetadataRetriever.OPTION_CLOSEST)
                        bitmap ?: error("Video frame unavailable")
                        try { encode(bitmap, Bitmap.CompressFormat.PNG) } finally { bitmap.recycle() }
                    }
                    "closeReader" -> { readers.remove(call.argument<String>("id"))?.release(); null }
                    "openWriter" -> {
                        val id = UUID.randomUUID().toString()
                        writers[id] = MovieEncoder(call.argument<String>("path")!!, call.argument<Int>("width")!!,
                            call.argument<Int>("height")!!, call.argument<Int>("fps") ?: 24)
                        id
                    }
                    "appendPixels" -> {
                        val writer=writers[call.argument<String>("id")]?:error("Writer closed")
                        writer.appendPixels(call.argument<ByteArray>("bytes")!!,call.argument<Int>("width")!!,call.argument<Int>("height")!!,call.argument<Boolean>("bgra")==true,call.argument<Number>("timeUs")!!.toLong());null
                    }
                    "appendFrame" -> {
                        val writer = writers[call.argument<String>("id")] ?: error("Writer closed")
                        val bytes = call.argument<ByteArray>("bytes")!!
                        val bitmap = BitmapFactory.decodeByteArray(bytes,0,bytes.size) ?: error("Invalid frame")
                        try { writer.append(bitmap, call.argument<Number>("timeUs")!!.toLong()) } finally { bitmap.recycle() }
                        null
                    }
                    "copyAudio" -> {
                        val path=call.argument<String>("path")!!
                        val sources=call.argument<List<Map<String,Any>>>("sources")!!
                        mapOf("hasAudio" to MovieAudio.merge(path,sources))
                    }
                    "finishWriter" -> {
                        val writer = writers.remove(call.argument<String>("id")) ?: error("Writer closed")
                        writer.finish(); writer.path
                    }
                    "abortWriter" -> { writers.remove(call.argument<String>("id"))?.abort(); null }
                    else -> throw UnsupportedOperationException(call.method)
                }
                main.post { result.success(value) }
            } catch(e: Exception) { main.post { result.error("MEDIA_FAILED", e.message ?: e.toString(), null) } }
        }
    }
    private fun encode(bitmap: Bitmap, format: Bitmap.CompressFormat): ByteArray = ByteArrayOutputStream().use {
        check(bitmap.compress(format, 95, it)); it.toByteArray()
    }
    private fun detectBoxes(image: InputImage): List<Face> =
        Tasks.await(detector.process(image))
            .sortedByDescending { it.boundingBox.width() * it.boundingBox.height() }
            .take(faceLimit)

    private fun detectBitmap(bitmap: Bitmap): List<Map<String, Any>> =
        describeFaces(bitmap, detectBoxes(InputImage.fromBitmap(bitmap, 0)))

    private fun describeFaces(bitmap: Bitmap, faces: List<Face>): List<Map<String, Any>> =
        faces.map { face ->
            val b = face.boundingBox
            val width = bitmap.width.toDouble()
            val height = bitmap.height.toDouble()
            val geometry = runCatching { contourFor(bitmap, b) }.getOrNull()
            val points = geometry?.first.orEmpty()
            val lips = geometry?.second.orEmpty()
            val candidates = points.filter { it.y in (b.top+b.height()*.48f)..(b.top+b.height()*.84f) }
            val left = candidates.minByOrNull { it.x } ?: PointF(b.left+b.width()*.08f,b.top+b.height()*.66f)
            val right = candidates.maxByOrNull { it.x } ?: PointF(b.right-b.width()*.08f,b.top+b.height()*.66f)
            val mouth = if(lips.isNotEmpty()) listOf(lips.map{it.x/width}.average(),lips.map{it.y/height}.average()) else emptyList<Double>()
            mapOf("outline" to points.map { listOf(it.x/width,it.y/height) }, "mouth" to mouth,
                "box" to listOf(b.left/width,b.top/height,b.width()/width,b.height()/height),
                "jaw" to listOf(left.x/width,left.y/height,right.x/width,right.y/height))
        }

    // ML Kit contour mode returns only the dominant face. Crop each detected
    // face separately, then reject a contour if the crop picked a neighbor.
    private fun contourFor(bitmap: Bitmap, box: Rect): Pair<List<PointF>, List<PointF>>? {
        val crop = Rect(box).apply {
            inset(-maxOf(2, (width() * .22f).toInt()), -maxOf(2, (height() * .24f).toInt()))
        }
        if (!crop.intersect(0, 0, bitmap.width, bitmap.height)) return null
        val scale = 320f / maxOf(crop.width(), crop.height())
        val width = maxOf(1, (crop.width() * scale).toInt())
        val height = maxOf(1, (crop.height() * scale).toInt())
        val sample = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            Canvas(sample).drawBitmap(bitmap, crop, Rect(0, 0, width, height), Paint(Paint.FILTER_BITMAP_FLAG))
            val contour = Tasks.await(contourDetector.process(InputImage.fromBitmap(sample, 0)))
                .firstOrNull() ?: return null
            val sx = crop.width().toFloat() / width
            val sy = crop.height().toFloat() / height
            fun restore(p: PointF) = PointF(crop.left + p.x * sx, crop.top + p.y * sy)
            val b = contour.boundingBox
            val mapped = RectF(crop.left + b.left * sx, crop.top + b.top * sy,
                crop.left + b.right * sx, crop.top + b.bottom * sy)
            val intersection = RectF(mapped)
            if (!intersection.intersect(RectF(box))) return null
            val overlap = intersection.width() * intersection.height()
            val union = mapped.width() * mapped.height() + box.width() * box.height() - overlap
            if (overlap < .35f * union) return null
            val outline = contour.getContour(FaceContour.FACE)?.points.orEmpty()
            val lips = contour.getContour(FaceContour.UPPER_LIP_BOTTOM)?.points.orEmpty() +
                contour.getContour(FaceContour.LOWER_LIP_TOP)?.points.orEmpty()
            return outline.map(::restore) to lips.map(::restore)
        } finally {
            sample.recycle()
        }
    }
}
