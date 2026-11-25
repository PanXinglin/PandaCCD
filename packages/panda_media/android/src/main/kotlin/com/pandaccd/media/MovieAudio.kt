package com.pandaccd.media

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/** Copy original encoded audio; no audio re-encoding or microphone access. */
internal object MovieAudio {
    fun merge(videoPath:String,sources:List<Map<String,Any>>):Boolean {
        var audioFormat:MediaFormat?=null
        for(s in sources) {
            val e=MediaExtractor()
            try {e.setDataSource(s["path"] as String);for(i in 0 until e.trackCount) {
                val f=e.getTrackFormat(i);if(f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/")==true){audioFormat=f;break}
            }} finally{e.release()}
            if(audioFormat!=null)break
        }
        if(audioFormat==null)return false
        val target="$videoPath.audio.mp4";File(target).delete()
        val muxer=MediaMuxer(target,MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val video=MediaExtractor();var started=false;var samples=0
        try {
            video.setDataSource(videoPath)
            val v=(0 until video.trackCount).first{video.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/")==true}
            video.selectTrack(v);val vt=muxer.addTrack(video.getTrackFormat(v));val at=muxer.addTrack(audioFormat)
            muxer.start();started=true
            val buffer=ByteBuffer.allocateDirect(4*1024*1024);val info=MediaCodec.BufferInfo()
            while(true) {
                buffer.clear();val size=video.readSampleData(buffer,0);if(size<0)break
                info.set(0,size,video.sampleTime,video.sampleFlags);muxer.writeSampleData(vt,buffer,info);video.advance()
            }
            var last=-1L
            for(s in sources) {
                val reader=MediaExtractor()
                try {
                    reader.setDataSource(s["path"] as String)
                    val index=(0 until reader.trackCount).firstOrNull{reader.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/")==true}?:continue
                    reader.selectTrack(index)
                    val from=(s["fromUs"] as Number).toLong();val to=(s["toUs"] as Number).toLong();val offset=(s["offsetUs"] as Number).toLong()
                    reader.seekTo(from,MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                    while(true) {
                        val time=reader.sampleTime;if(time<0||time>=to)break
                        buffer.clear();val size=reader.readSampleData(buffer,0);if(size<0)break
                        if(time>=from) {
                            val pts=maxOf(last+1,time-from+offset);info.set(0,size,pts,reader.sampleFlags)
                            muxer.writeSampleData(at,buffer,info);last=pts;samples++
                        }
                        reader.advance()
                    }
                }finally{reader.release()}
            }
        }catch(e:Exception){File(target).delete();throw e}
        finally{video.release();if(started)runCatching{muxer.stop()};muxer.release()}
        if(samples==0){File(target).delete();return false}
        check(File(target).renameTo(File(videoPath))){"Could not install audio movie"};return true
    }
}
