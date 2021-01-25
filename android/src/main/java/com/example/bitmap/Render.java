package com.example.bitmap;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Matrix;
import android.graphics.SurfaceTexture;
import android.opengl.GLES20;
import android.opengl.GLUtils;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;

import androidx.annotation.RequiresApi;

import com.bumptech.glide.Glide;
import com.bumptech.glide.request.FutureTarget;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.concurrent.ExecutionException;

import javax.microedition.khronos.egl.EGL10;
import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.egl.EGLContext;
import javax.microedition.khronos.egl.EGLDisplay;
import javax.microedition.khronos.egl.EGLSurface;

import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.view.TextureRegistry;

public class Render {
  private final Context context;
  private final TextureRegistry.SurfaceTextureEntry entry;
  private final SurfaceTexture surfaceTexture;
  private final long textureId;

  private final HandlerThread handlerThread;
  private final Handler handler;

  private EGL10 egl;
  private EGLDisplay eglDisplay;
  private EGLContext eglContext;
  private EGLSurface eglSurface;

  private FloatBuffer vertexBuffer;
  private FloatBuffer textureBuffer;
  static final float[] vertexData = {
    -1f, -1f, 0.0f,
     1f, -1f, 0.0f,
    -1f,  1f, 0.0f,
     1f,  1f, 0.0f,
  };
  static final float[] textureData = {
    0f, 1f, 0.0f,
    1f, 1f, 0.0f,
    0f, 0f, 0.0f,
    1f, 0f, 0.0f,
  };
  static final int COORS_PER_VERTEX = 3;
  static final int vertexCount = vertexData.length / COORS_PER_VERTEX;
  static final int vertexStride = COORS_PER_VERTEX * 4;

  int vertexShader;
  int fragmentShader;

  private int program;

  private Bitmap bitmap;

  public Render(Context context, TextureRegistry.SurfaceTextureEntry entry, SurfaceTexture surfaceTexture, long textureId) {
    this.context = context;
    this.entry = entry;
    this.surfaceTexture = surfaceTexture;
    this.textureId = textureId;

    handlerThread = new HandlerThread("Render");
    handlerThread.start();
    handler = new Handler(handlerThread.getLooper());
    handler.post(new Runnable() {
      @Override
      public void run() {
        init();
      }
    });
  }

  /// value is the path of bitmap.
  public void r(final Result result, final String path, final int width, final int height, final int fit, final String value, final Boolean findCache) {
    handler.post(new Runnable() {
      @Override
      public void run() {
        render(result, path, width, height, fit, value, findCache);
      }
    });
  }

  /// dispose all and wait the end of HandlerThread.
  @RequiresApi(api = Build.VERSION_CODES.JELLY_BEAN_MR2)
  public void d() throws InterruptedException {
    handler.post(new Runnable() {
      @Override
      public void run() {
        dispose();
      }
    });
    handlerThread.quitSafely();
    handlerThread.join();
    entry.release();
  }

  private void init() {
    initOpenGL();
    initProgram();
    initTexture();
  }

  private void initOpenGL() {
    egl = (EGL10) EGLContext.getEGL();
    eglDisplay = egl.eglGetDisplay(EGL10.EGL_DEFAULT_DISPLAY);
    if (eglDisplay == EGL10.EGL_NO_DISPLAY) {
      throw new RuntimeException("Can not run eglGetDisplay");
    }

    int[] version = new int[2];
    if (!egl.eglInitialize(eglDisplay, version)) {
      throw new RuntimeException("Can not run eglInitialize");
    }

    EGLConfig eglConfig = chooseEglConfig();
    eglContext = createContext(egl, eglDisplay, eglConfig);

    eglSurface = egl.eglCreateWindowSurface(eglDisplay, eglConfig, surfaceTexture, null);
    if (eglSurface == null || eglSurface == EGL10.EGL_NO_SURFACE) {
      throw new RuntimeException("Can not run eglCreateWindowSurface");
    }
    
    if (!egl.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
      throw new RuntimeException("Can not run eglMakeCurrent");
    }
  }

  private EGLConfig chooseEglConfig() {
    int[] configsCount = new int[1];
    EGLConfig[] configs = new EGLConfig[1];
    int[] configSpec = getConfig();

    if (!egl.eglChooseConfig(eglDisplay, configSpec, configs, 1, configsCount)) {
      throw new IllegalArgumentException("Can not run eglChooseConfig");
    } else if (configsCount[0] > 0) {
      return configs[0];
    }

    return null;
  }

  private int[] getConfig() {
    return new int[] {
      EGL10.EGL_RENDERABLE_TYPE, 4,
      EGL10.EGL_RED_SIZE, 8,
      EGL10.EGL_GREEN_SIZE, 8,
      EGL10.EGL_BLUE_SIZE, 8,
      EGL10.EGL_ALPHA_SIZE, 8,
      EGL10.EGL_DEPTH_SIZE, 16,
      EGL10.EGL_STENCIL_SIZE, 0,
      EGL10.EGL_SAMPLE_BUFFERS, 1,
      EGL10.EGL_SAMPLES, 4,
      EGL10.EGL_NONE
    };
  }

  private EGLContext createContext(EGL10 egl, EGLDisplay eglDisplay, EGLConfig eglConfig) {
    int EGL_CONTEXT_CLIENT_VERSION = 0x3098;
    int[] attributeList = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL10.EGL_NONE};
    return egl.eglCreateContext(eglDisplay, eglConfig, EGL10.EGL_NO_CONTEXT, attributeList);
  }

  private void initProgram() {
    vertexBuffer = ByteBuffer.allocateDirect(vertexData.length * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .put(vertexData);
    vertexBuffer.position(0);

    textureBuffer = ByteBuffer.allocateDirect(textureData.length * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .put(textureData);
    textureBuffer.position(0);

    String vertexSource = readShader(context, R.raw.vertex_shader);
    String fragmentSource = readShader(context, R.raw.fragment_shader);
    program = createProgram(vertexSource, fragmentSource);
  }

  public static String readShader(Context context, int resource) {
    InputStream inputStream = context.getResources().openRawResource(resource);
    BufferedReader reader = new BufferedReader(new InputStreamReader(inputStream));
    StringBuilder sb = new StringBuilder();
    String line;
    try {
      while ((line = reader.readLine()) != null) {
        sb.append(line).append("\n");
      }
      reader.close();
    } catch (Exception e) {
      e.printStackTrace();
    }
    return sb.toString();
  }

  private int createProgram(String vertexSource, String fragmentSource) {
    vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, vertexSource);
    if (vertexShader == 0) {
      return 0;
    }
    fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource);
    if (fragmentShader == 0) {
      return 0;
    }

    int program = GLES20.glCreateProgram();
    if (program != 0) {
      GLES20.glAttachShader(program, vertexShader);
      GLES20.glAttachShader(program, fragmentShader);
      GLES20.glLinkProgram(program);
      int[] status = new int[1];
      GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, status, 0);
      if (status[0] != GLES20.GL_TRUE) {
        GLES20.glDeleteProgram(program);
        program = 0;
      }
    }
    return program;
  }

  private int loadShader(int type, String source) {
    int shader = GLES20.glCreateShader(type);
    if (shader != 0) {
      GLES20.glShaderSource(shader, source);
      GLES20.glCompileShader(shader);
      int[] compile = new int[1];
      GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compile, 0);
      if (compile[0] != GLES20.GL_TRUE) {
        GLES20.glDeleteShader(shader);
        shader = 0;
      }
    }
    return shader;
  }

  private void initTexture() {
    int avPosition = GLES20.glGetAttribLocation(program, "av_Position");
    int afPosition = GLES20.glGetAttribLocation(program, "af_Position");
    GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, (int) textureId);

    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_REPEAT);
    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_REPEAT);

    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR);
    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR);
    
    GLES20.glClearColor(0.f, 0.f, 0.f, 1.f);
    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT | GLES20.GL_DEPTH_BUFFER_BIT);
    GLES20.glUseProgram(program);
    GLES20.glEnableVertexAttribArray(avPosition);
    GLES20.glEnableVertexAttribArray(afPosition);
    GLES20.glVertexAttribPointer(avPosition, COORS_PER_VERTEX, GLES20.GL_FLOAT, false, vertexStride, vertexBuffer);
    GLES20.glVertexAttribPointer(afPosition, COORS_PER_VERTEX, GLES20.GL_FLOAT, false, vertexStride, textureBuffer);
  }

  private void render(final Result result, String path, int width, int height, int fit, String value, Boolean findCache) {
    makeBitMap(path, width, height, fit, value, findCache);

    if (bitmap != null && !bitmap.isRecycled()) {
      GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0);
    }
    GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, vertexCount);
    egl.eglSwapBuffers(eglDisplay, eglSurface);

    new Handler(Looper.getMainLooper()).post(new Runnable() {
      @Override
      public void run() {
        result.success(textureId);
      }
    });
  }

  private void makeBitMap(String path, int width, int height, int fit, String value, Boolean findCache) {
    if (!findCache) {
      FutureTarget<Bitmap> bitmapFutureTarget = Glide.with(context).asBitmap().load(path).submit();
      try {
        bitmap = bitmapFutureTarget.get();
      } catch (InterruptedException ignored) {
      } catch (ExecutionException ignored) {
      }

      switch (fit) {
        case 0:
        case 2:
        default:
          bitmap = resizeCrop(bitmap, width, height);
          break;
      }

      try {
        FileOutputStream out = new FileOutputStream(value);
        ByteBuffer colors = ByteBuffer.allocate(height * width * 4);
        bitmap.copyPixelsToBuffer(colors);
        out.write(colors.array());
      }
      catch (IOException ignored) {
      }
    }
    else {
      // rgba
      ByteBuffer colors = ByteBuffer.allocate(height * width * 4);
      // value is the path of bitmap.
      File file = new File(value);
      try {
        FileInputStream in = new FileInputStream(file);
        int size = in.read(colors.array());
        if (size > 0) {
          bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
          bitmap.copyPixelsFromBuffer(colors);
        }
      }
      catch (IOException ignored) {
      }
    }
  }

  private Bitmap resizeCrop(Bitmap bitmap, int width, int height) {
    int srcWidth = bitmap.getWidth();
    int srcHeight = bitmap.getHeight();
    float scale = Math.max(width / srcWidth, height / srcHeight);
    int dstWidth = Math.round(srcWidth * scale);
    int dstHeight = Math.round(srcHeight * scale);
    int x = (dstWidth - width) / 2;
    int y = (dstHeight - height) / 2;
    Matrix matrix = new Matrix();
    matrix.postScale(scale, scale);
    bitmap = Bitmap.createBitmap(bitmap, 0, 0, dstWidth, dstHeight, matrix, false);
    bitmap = Bitmap.createBitmap(bitmap, x, y, width, height);
    return bitmap;
  }

  private void dispose() {
    egl.eglWaitGL();
    egl.eglMakeCurrent(eglDisplay, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_CONTEXT);
    egl.eglDestroySurface(eglDisplay, eglSurface);
    egl.eglDestroyContext(eglDisplay, eglContext);
    egl.eglTerminate(eglDisplay);
  }
}