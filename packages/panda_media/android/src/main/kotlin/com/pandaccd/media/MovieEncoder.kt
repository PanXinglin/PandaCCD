package com.pandaccd.media

import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.opengl.*
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** PNG -> hardware video surface. Shader is only an unmodified pixel blit. */
internal class MovieEncoder(val path: String, private val width: Int, private val height: Int, fps: Int) {
    private val codec = MediaCodec.createEncoderByType("video/avc")
    private val muxer = MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    private var track = -1
    private var started = false
    private var released = false
    private val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
    private val context: android.opengl.EGLContext
    private val surface: android.opengl.EGLSurface
    private val input: android.view.Surface
    private val program: Int
    private val texture: Int
    private val vertices = ByteBuffer.allocateDirect(16*4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
        put(floatArrayOf(-1f,-1f,0f,1f, 1f,-1f,1f,1f, -1f,1f,0f,0f, 1f,1f,1f,0f)); position(0)
    }
    init {
        require(width > 0 && height > 0 && width%2==0 && height%2==0)
        val format = MediaFormat.createVideoFormat("video/avc",width,height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT,MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE,4_000_000); setInteger(MediaFormat.KEY_FRAME_RATE,fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL,1)
        }
        codec.configure(format,null,null,MediaCodec.CONFIGURE_FLAG_ENCODE)
        input = codec.createInputSurface(); codec.start()
        check(EGL14.eglInitialize(display,IntArray(2),0,IntArray(2),0))
        val configs = arrayOfNulls<android.opengl.EGLConfig>(1)
        check(EGL14.eglChooseConfig(display,intArrayOf(EGL14.EGL_RED_SIZE,8,EGL14.EGL_GREEN_SIZE,8,EGL14.EGL_BLUE_SIZE,8,
            EGL14.EGL_RENDERABLE_TYPE,EGL14.EGL_OPENGL_ES2_BIT,0x3142,1,EGL14.EGL_NONE),0,configs,0,1,IntArray(1),0))
        context = EGL14.eglCreateContext(display,configs[0],EGL14.EGL_NO_CONTEXT,intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION,2,EGL14.EGL_NONE),0)
        surface = EGL14.eglCreateWindowSurface(display,configs[0],input,intArrayOf(EGL14.EGL_NONE),0)
        check(EGL14.eglMakeCurrent(display,surface,surface,context))
        fun compile(type:Int,source:String):Int { val id=GLES20.glCreateShader(type); GLES20.glShaderSource(id,source); GLES20.glCompileShader(id)
            val ok=IntArray(1); GLES20.glGetShaderiv(id,GLES20.GL_COMPILE_STATUS,ok,0); check(ok[0]!=0){GLES20.glGetShaderInfoLog(id)};return id }
        val vs=compile(GLES20.GL_VERTEX_SHADER,"attribute vec2 p;attribute vec2 t;varying vec2 uv;void main(){gl_Position=vec4(p,0.,1.);uv=t;}")
        val fs=compile(GLES20.GL_FRAGMENT_SHADER,"precision mediump float;varying vec2 uv;uniform sampler2D image;uniform float bgra;void main(){vec4 c=texture2D(image,uv);gl_FragColor=bgra>.5?c.bgra:c;}")
        program=GLES20.glCreateProgram(); GLES20.glAttachShader(program,vs);GLES20.glAttachShader(program,fs); GLES20.glLinkProgram(program)
        GLES20.glDeleteShader(vs);GLES20.glDeleteShader(fs)
        val ids=IntArray(1);GLES20.glGenTextures(1,ids,0);texture=ids[0]
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D,texture)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D,GLES20.GL_TEXTURE_MIN_FILTER,GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D,GLES20.GL_TEXTURE_MAG_FILTER,GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D,GLES20.GL_TEXTURE_WRAP_S,GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D,GLES20.GL_TEXTURE_WRAP_T,GLES20.GL_CLAMP_TO_EDGE)
    }
    fun appendPixels(bytes:ByteArray,w:Int,h:Int,bgra:Boolean,timeUs:Long) {
        check(!released);drain(false);check(EGL14.eglMakeCurrent(display,surface,surface,context))
        GLES20.glViewport(0,0,width,height);GLES20.glUseProgram(program)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0);GLES20.glBindTexture(GLES20.GL_TEXTURE_2D,texture)
        GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D,0,GLES20.GL_RGBA,w,h,0,GLES20.GL_RGBA,GLES20.GL_UNSIGNED_BYTE,ByteBuffer.wrap(bytes))
        draw(timeUs,bgra)
    }
    fun append(bitmap: Bitmap, timeUs: Long) {
        check(!released)
        drain(false)
        check(EGL14.eglMakeCurrent(display,surface,surface,context))
        GLES20.glViewport(0,0,width,height); GLES20.glUseProgram(program)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0);GLES20.glBindTexture(GLES20.GL_TEXTURE_2D,texture)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D,0,bitmap,0)
        draw(timeUs,false)
    }
    private fun draw(timeUs:Long,bgra:Boolean) {
        GLES20.glUniform1f(GLES20.glGetUniformLocation(program,"bgra"),if(bgra)1f else 0f)
        val p=GLES20.glGetAttribLocation(program,"p");val t=GLES20.glGetAttribLocation(program,"t")
        vertices.position(0);GLES20.glVertexAttribPointer(p,2,GLES20.GL_FLOAT,false,16,vertices);GLES20.glEnableVertexAttribArray(p)
        vertices.position(2);GLES20.glVertexAttribPointer(t,2,GLES20.GL_FLOAT,false,16,vertices);GLES20.glEnableVertexAttribArray(t)
        GLES20.glUniform1i(GLES20.glGetUniformLocation(program,"image"),0);GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP,0,4)
        EGLExt.eglPresentationTimeANDROID(display,surface,timeUs*1000)
        check(EGL14.eglSwapBuffers(display,surface));drain(false)
    }
    private fun drain(end: Boolean) {
        val info=MediaCodec.BufferInfo();val deadline=System.nanoTime()+10_000_000_000L
        while(true) {
            val index=codec.dequeueOutputBuffer(info,if(end)10_000L else 0L)
            if(index==MediaCodec.INFO_TRY_AGAIN_LATER) { if(!end)return;check(System.nanoTime()<deadline){"Video encoder timed out"};continue }
            if(index==MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) { check(!started);track=muxer.addTrack(codec.outputFormat);muxer.start();started=true;continue }
            if(index<0)continue
            val buffer=codec.getOutputBuffer(index)!!
            if(info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0)info.size=0
            if(info.size>0) { check(started);buffer.position(info.offset);buffer.limit(info.offset+info.size);muxer.writeSampleData(track,buffer,info) }
            val done=info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
            codec.releaseOutputBuffer(index,false);if(done)return
        }
    }
    fun finish() { try {codec.signalEndOfInputStream();drain(true)} finally {release()} }
    fun abort() { release();File(path).delete() }
    private fun release() {
        if(released)return;released=true
        runCatching { codec.stop() };codec.release();runCatching {if(started)muxer.stop()};muxer.release()
        runCatching {GLES20.glDeleteProgram(program);GLES20.glDeleteTextures(1,intArrayOf(texture),0)}
        EGL14.eglMakeCurrent(display,EGL14.EGL_NO_SURFACE,EGL14.EGL_NO_SURFACE,EGL14.EGL_NO_CONTEXT)
        EGL14.eglDestroySurface(display,surface);EGL14.eglDestroyContext(display,context);EGL14.eglTerminate(display);input.release()
    }
}
