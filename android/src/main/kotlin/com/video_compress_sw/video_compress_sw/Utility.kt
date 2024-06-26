package com.video_compress_sw.video_compress_sw

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import kotlin.math.max


class Utility(private val channelName: String) {

    private fun isLandscapeImage(orientation: Int) = orientation != 90 && orientation != 270

    fun deleteFile(file: File) {
        if (file.exists()) {
            file.delete()
        }
    }

    fun timeStrToTimestamp(time: String): Long {
        val timeArr = time.split(":")
        val hour = Integer.parseInt(timeArr[0])
        val min = Integer.parseInt(timeArr[1])
        val secArr = timeArr[2].split(".")
        val sec = Integer.parseInt(secArr[0])
        val mSec = Integer.parseInt(secArr[1])

        val timeStamp = (hour * 3600 + min * 60 + sec) * 1000 + mSec
        return timeStamp.toLong()
    }

    fun getMediaInfoJson(context: Context, path: String): JSONObject {
        val file = File(path)
        val retriever = MediaMetadataRetriever()

        retriever.setDataSource(context, Uri.fromFile(file))

        val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
        val title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE) ?: ""
        val author = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_AUTHOR) ?: ""
        val widthStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
        val heightStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
        val duration = java.lang.Long.parseLong(durationStr?:"0")
        var width = java.lang.Long.parseLong(widthStr?:"0")
        var height = java.lang.Long.parseLong(heightStr?:"0")
        val filesize = file.length()
        val orientation =
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
        val ori = orientation?.toIntOrNull()
        if (ori != null && isLandscapeImage(ori)) {
            val tmp = width
            width = height
            height = tmp
        }

        retriever.release()

        val json = JSONObject()

        json.put("path", path)
        json.put("title", title)
        json.put("author", author)
        json.put("width", width)
        json.put("height", height)
        json.put("duration", duration)
        json.put("filesize", filesize)
        if (ori != null) {
            json.put("orientation", ori)
        }

        return json
    }

     private fun setDataSource(videoPath: String, retriever:MediaMetadataRetriever  ) {

        val path: String = if (videoPath.startsWith("/")) {
            videoPath
        } else if (videoPath.startsWith("file://")) {
            videoPath.substring(7)
        } else {
            retriever.setDataSource(videoPath)
            return
        }

        val videoFile = File(path)
        val inputStream = FileInputStream(videoFile.absolutePath)
        retriever.setDataSource(inputStream.fd)
    }

    fun getBitmap(path: String, position: Long, maxWidth: Int, maxHeight: Int, result: MethodChannel.Result): Bitmap {
        var bitmap: Bitmap? = null
        val retriever = MediaMetadataRetriever()

        try {
            setDataSource(path,retriever )

            if (android.os.Build.VERSION.SDK_INT >= 27 && maxWidth > 0 && maxHeight > 0) {
                bitmap = retriever.getScaledFrameAtTime(
                    position * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    maxWidth, maxHeight
                )
            } else {
                bitmap = retriever.getFrameAtTime(position * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                bitmap?.let {
                    if (maxWidth > 0 || maxHeight > 0) {
                        val ratio = if (maxWidth > 0 && maxHeight > 0) {
                            Math.min(maxWidth.toDouble() / it.width, maxHeight.toDouble() / it.height)
                        } else if (maxWidth > 0) {
                            maxWidth.toDouble() / it.width
                        } else {
                            maxHeight.toDouble() / it.height
                        }
                        val newWidth = (it.width * ratio).toInt()
                        val newHeight = (it.height * ratio).toInt()
                        bitmap = Bitmap.createScaledBitmap(it, newWidth, newHeight, true)
                    }
                }
            }

        } catch (ex: IllegalArgumentException) {
            result.error(channelName, "Assume this is a corrupt video file", null)
        } catch (ex: RuntimeException) {
            result.error(channelName, "Assume this is a corrupt video file", null)
        } finally {
            try {
                retriever.release()
            } catch (ex: RuntimeException) {
                result.error(channelName, "Ignore failures while cleaning up", null)
            }
        }

        if (bitmap == null) result.success(emptyArray<Int>())

//        val width = bitmap!!.width
//        val height = bitmap.height
//        val max = max(width, height)
//        if (max > 512) {
//            val scale = 512f / max
//            val w = Math.round(scale * width)
//            val h = Math.round(scale * height)
//            bitmap = Bitmap.createScaledBitmap(bitmap, w, h, true)
//        }

        return bitmap!!
    }

    fun getFileNameWithGifExtension(path: String): String {
        val file = File(path)
        var fileName = ""
        val gifSuffix = "gif"
        val dotGifSuffix = ".$gifSuffix"

        if (file.exists()) {
            val name = file.name
            fileName = name.replaceAfterLast(".", gifSuffix)

            if (!fileName.endsWith(dotGifSuffix)) {
                fileName += dotGifSuffix
            }
        }
        return fileName
    }

    fun deleteAllCache(context: Context, result: MethodChannel.Result) {
        val dir = context.getExternalFilesDir("video_compress")
        result.success(dir?.deleteRecursively())
    }
}
