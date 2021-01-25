package com.example.bitmap;

import android.content.Context;
import android.graphics.SurfaceTexture;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;
import androidx.collection.LongSparseArray;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.view.TextureRegistry;

/** BitmapPlugin */
public class BitmapPlugin implements FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private MethodChannel channel;
  private TextureRegistry textures;
  private Context context;
  private final LongSparseArray<Render> renders = new LongSparseArray<>();  // LongSparseArray have better performance than HashMap.

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "bitmap");
    channel.setMethodCallHandler(this);

    textures = flutterPluginBinding.getTextureRegistry();
    context = flutterPluginBinding.getApplicationContext();
  }

  @RequiresApi(api = Build.VERSION_CODES.JELLY_BEAN_MR2)
  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    Map<String, Object> arguments = call.arguments();
    if (call.method.equals("r")) {  // render
      long textureId = ((Number) arguments.get("textureId")).longValue();
      String path = arguments.get("path").toString();
      int width = (int) (double) arguments.get("width");
      int height = (int) (double) arguments.get("height");
      int fit = (int) arguments.get("fit");
      String bitmap = arguments.get("bitmap").toString();
      boolean findCache = (boolean) arguments.get("findCache");

      if (textureId == -1) {  // Create a new texture
        TextureRegistry.SurfaceTextureEntry entry = textures.createSurfaceTexture();
        SurfaceTexture surfaceTexture = entry.surfaceTexture();
        surfaceTexture.setDefaultBufferSize(width, height);

        textureId = entry.id();
        Render render = new Render(context, entry, surfaceTexture, textureId);
        render.r(result, path, width, height, fit, bitmap, findCache);
        renders.put(textureId, render);
      }
      else {  // Just render
        Render render = renders.get(textureId);
        if (render != null) {
          render.r(result, path, width, height, fit, bitmap, findCache);
        }
      }
    }
    else if (call.method.equals("dl")) {  // Dispose list of texture.
      List<?> textureIdsArg = (List<?>) arguments.get("textureIds");
      List<Number> textureIds = new ArrayList<>();
      for (Object textureId : textureIdsArg) {
        textureIds.add((Number) textureId);
      }
      for (Number textureId : textureIds) {
        Render render = renders.get((textureId).longValue());
        if (render != null) {
          try {
            render.d();
          } catch (InterruptedException e) {
            e.printStackTrace();
          }
          renders.remove((textureId).longValue());
        }
      }
      result.success(null);
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
  }
}
